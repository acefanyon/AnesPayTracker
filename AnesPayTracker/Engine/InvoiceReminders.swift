import Foundation
import SwiftData
import UserNotifications

// MARK: - Settings

enum InvoiceSettingsKey {
    /// App-wide: invoices can be marked paid, and unpaid ones are reminded weekly.
    static let tracksPayments = "invoices.tracksPayments"
}

// MARK: - Due Periods

/// A finished invoice period with shifts that aren't on any invoice yet.
struct InvoiceDuePeriod: Identifiable {
    let employer: Employer
    let period: InvoicePeriod
    let shiftCount: Int
    let totalCents: Int

    var id: String { "\(employer.id.uuidString)-\(period.start.timeIntervalSinceReferenceDate)" }
}

/// Values for the new-invoice form when it is opened from a reminder.
struct InvoicePrefill: Identifiable {
    let id = UUID()
    let employerID: UUID
    let period: InvoicePeriod
}

// MARK: - Invoice Reminders

/// Works out which invoices are due, from the employer's invoice schedule and
/// the shifts not yet on an invoice. Reads only; never changes data.
enum InvoiceReminders {

    /// The employer's invoice period containing `date`, or nil when reminders
    /// are off or the schedule can't be worked out (a weekly schedule without
    /// its anchor, or pay periods that are only guesses).
    static func period(containing date: Date, for employer: Employer, calendar: Calendar = .current) -> InvoicePeriod? {
        guard let cadence = employer.invoiceCadence else { return nil }
        if cadence == .payPeriod {
            guard employer.hasReliablePayPeriods else { return nil }
            let (start, end) = StreakEngine.payPeriodBounds(containing: date, employer: employer)
            return InvoicePeriod(start: calendar.startOfDay(for: start), end: calendar.startOfDay(for: end))
        }
        return InvoiceScheduleMath.period(
            containing: date,
            cadence: cadence,
            anchorEnd: employer.invoicePeriodEndAnchor,
            calendar: calendar
        )
    }

    static func invoicedShiftIDs(_ invoices: [Invoice]) -> Set<UUID> {
        Set(InvoiceBuilder.invoiceNumbersByShift(invoices).keys)
    }

    /// Periods (finished or not) with worked shifts, up to today, that have
    /// something to bill and aren't on an invoice. Oldest first. Only shifts
    /// from the period containing the reminders' start date are considered.
    static func uninvoicedPeriods(
        for employer: Employer,
        invoicedShiftIDs: Set<UUID>,
        now: Date,
        calendar: Calendar = .current
    ) -> [(period: InvoicePeriod, shifts: [Shift])] {
        guard employer.invoiceCadence != nil,
              let firstPeriod = period(containing: employer.invoiceRemindersStartDate ?? now, for: employer, calendar: calendar)
        else { return [] }

        let endOfToday = calendar.endOfDay(for: now)
        var grouped: [InvoicePeriod: [Shift]] = [:]
        for shift in employer.sites.flatMap(\.shifts)
        where shift.date >= firstPeriod.start && shift.date <= endOfToday && !invoicedShiftIDs.contains(shift.id) {
            guard InvoiceBuilder.day(for: shift).totalCents > 0,
                  let shiftPeriod = period(containing: shift.date, for: employer, calendar: calendar) else { continue }
            grouped[shiftPeriod, default: []].append(shift)
        }
        return grouped
            .sorted { $0.key.start < $1.key.start }
            .map { (period: $0.key, shifts: $0.value.sorted { $0.date < $1.date }) }
    }

    /// Finished periods that still need an invoice, for every employer with
    /// reminders on. Oldest first.
    static func duePeriods(employers: [Employer], invoices: [Invoice], now: Date = Date(), calendar: Calendar = .current) -> [InvoiceDuePeriod] {
        let invoiced = invoicedShiftIDs(invoices)
        return employers.flatMap { employer in
            uninvoicedPeriods(for: employer, invoicedShiftIDs: invoiced, now: now, calendar: calendar)
                .filter { InvoiceScheduleMath.hasEnded($0.period, now: now, calendar: calendar) }
                .map { entry in
                    InvoiceDuePeriod(
                        employer: employer,
                        period: entry.period,
                        shiftCount: entry.shifts.count,
                        totalCents: entry.shifts.reduce(0) { $0 + InvoiceBuilder.day(for: $1).totalCents }
                    )
                }
        }
        .sorted { $0.period.end < $1.period.end }
    }

    static func unpaidInvoices(_ invoices: [Invoice]) -> [Invoice] {
        invoices.filter { $0.paidOn == nil }.sorted { $0.issuedOn < $1.issuedOn }
    }

    static func periodLabel(_ period: InvoicePeriod) -> String {
        let start = period.start.formatted(.dateTime.month(.abbreviated).day())
        let end = period.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }
}

// MARK: - Notifications

/// Keeps the app's pending invoice notifications in step with the data. Local
/// notifications can't check anything when they fire, so the whole set is
/// rebuilt whenever the app becomes active or goes to the background.
@MainActor
enum InvoiceNotificationScheduler {
    static let identifierPrefix = "invoice-reminder."
    static let reminderHour = 9
    static let remindersPerItem = 6
    /// iOS keeps at most 64 pending notifications per app.
    static let maximumPending = 60

    private struct Planned {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    /// Asks for permission only when the user turns a reminder on.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func reschedule(context: ModelContext, now: Date = Date()) async {
        let calendar = Calendar.current
        let employers = (try? context.fetch(FetchDescriptor<Employer>())) ?? []
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let tracksPayments = UserDefaults.standard.bool(forKey: InvoiceSettingsKey.tracksPayments)

        // Read everything from the models before the first await.
        var planned: [Planned] = []
        let invoiced = InvoiceReminders.invoicedShiftIDs(invoices)
        for employer in employers {
            for entry in InvoiceReminders.uninvoicedPeriods(for: employer, invoicedShiftIDs: invoiced, now: now, calendar: calendar) {
                let firstDay = InvoiceScheduleMath.firstInvoiceReminderDay(after: entry.period, calendar: calendar)
                let dates = InvoiceScheduleMath.weeklyReminders(
                    startingOn: firstDay, hour: reminderHour, after: now, limit: remindersPerItem, calendar: calendar
                )
                for (index, date) in dates.enumerated() {
                    planned.append(Planned(
                        id: "\(identifierPrefix)due.\(employer.id.uuidString).\(Int(entry.period.start.timeIntervalSinceReferenceDate)).\(index)",
                        date: date,
                        title: "Time to invoice \(employer.name)",
                        body: "Shifts from \(InvoiceReminders.periodLabel(entry.period)) aren't on an invoice yet."
                    ))
                }
            }
        }
        if tracksPayments {
            for invoice in InvoiceReminders.unpaidInvoices(invoices) {
                let firstDay = InvoiceScheduleMath.firstUnpaidReminderDay(issuedOn: invoice.issuedOn, dueOn: invoice.dueOn, calendar: calendar)
                let dates = InvoiceScheduleMath.weeklyReminders(
                    startingOn: firstDay, hour: reminderHour, after: now, limit: remindersPerItem, calendar: calendar
                )
                let issued = invoice.issuedOn.formatted(.dateTime.month(.abbreviated).day())
                for (index, date) in dates.enumerated() {
                    planned.append(Planned(
                        id: "\(identifierPrefix)unpaid.\(invoice.id.uuidString).\(index)",
                        date: date,
                        title: "Invoice \(invoice.number) isn't marked paid",
                        body: "Sent to \(invoice.billToName) on \(issued). Mark it paid in AnesPay when the payment arrives."
                    ))
                }
            }
        }
        planned = Array(planned.sorted { $0.date < $1.date }.prefix(maximumPending))

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
