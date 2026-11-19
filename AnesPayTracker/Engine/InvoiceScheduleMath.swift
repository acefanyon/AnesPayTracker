import Foundation

// Foundation only: this file is also compiled on its own by
// scripts/swift_tests/pay_math, so it must not import SwiftUI or SwiftData.

// MARK: - Invoice Cadence

/// How often an employer should be invoiced. Stored on `Employer`; nil means
/// no invoice reminders. Raw values are persisted: never rename them.
enum InvoiceCadence: String, Codable, CaseIterable, Identifiable {
    case weekly
    case everyTwoWeeks
    case twiceMonthly
    case monthly
    /// The employer's own pay periods (`StreakEngine.payPeriodBounds`).
    case payPeriod

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Every week"
        case .everyTwoWeeks: return "Every 2 weeks"
        case .twiceMonthly: return "Twice a month (1st–15th, 16th–end)"
        case .monthly: return "Every month"
        case .payPeriod: return "Each pay period"
        }
    }

    /// Weekly schedules need one known period end date to line up with.
    var needsAnchor: Bool { self == .weekly || self == .everyTwoWeeks }

    var lengthInDays: Int? {
        switch self {
        case .weekly: return 7
        case .everyTwoWeeks: return 14
        case .twiceMonthly, .monthly, .payPeriod: return nil
        }
    }
}

/// One billing period, first and last day inclusive (both at start of day).
struct InvoicePeriod: Equatable, Hashable {
    var start: Date
    var end: Date
}

// MARK: - Invoice Schedule Math

enum InvoiceScheduleMath {

    /// The period containing `date`, or nil when it can't be worked out here
    /// (`.payPeriod`, which the app takes from the pay-period engine, or a
    /// weekly schedule without its anchor).
    static func period(containing date: Date, cadence: InvoiceCadence, anchorEnd: Date?, calendar: Calendar) -> InvoicePeriod? {
        let day = calendar.startOfDay(for: date)
        switch cadence {
        case .weekly, .everyTwoWeeks:
            guard let anchorEnd, let length = cadence.lengthInDays else { return nil }
            let anchor = calendar.startOfDay(for: anchorEnd)
            let offset = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
            // Periods end on anchor + k × length; find the first end on or after `day`.
            let k = ceilDiv(offset, length)
            guard let end = calendar.date(byAdding: .day, value: k * length, to: anchor),
                  let start = calendar.date(byAdding: .day, value: -(length - 1), to: end) else { return nil }
            return InvoicePeriod(start: start, end: end)

        case .twiceMonthly:
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let monthStart = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) else { return nil }
            if (parts.day ?? 1) <= 15 {
                guard let fifteenth = calendar.date(byAdding: .day, value: 14, to: monthStart) else { return nil }
                return InvoicePeriod(start: monthStart, end: fifteenth)
            }
            guard let sixteenth = calendar.date(byAdding: .day, value: 15, to: monthStart),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                  let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return nil }
            return InvoicePeriod(start: sixteenth, end: monthEnd)

        case .monthly:
            let parts = calendar.dateComponents([.year, .month], from: day)
            guard let monthStart = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                  let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return nil }
            return InvoicePeriod(start: monthStart, end: monthEnd)

        case .payPeriod:
            return nil
        }
    }

    /// Whether the period is over by `now` (its last day has passed).
    static func hasEnded(_ period: InvoicePeriod, now: Date, calendar: Calendar) -> Bool {
        period.end < calendar.startOfDay(for: now)
    }

    // MARK: Reminders

    /// The first day to remind about a period that hasn't been invoiced: the
    /// day after it ends.
    static func firstInvoiceReminderDay(after period: InvoicePeriod, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: period.end) ?? period.end
    }

    /// The first day to remind about an unpaid invoice: its due date, or a
    /// week after the invoice date when it has none.
    static func firstUnpaidReminderDay(issuedOn: Date, dueOn: Date?, calendar: Calendar) -> Date {
        if let dueOn { return calendar.startOfDay(for: dueOn) }
        let issued = calendar.startOfDay(for: issuedOn)
        return calendar.date(byAdding: .day, value: 7, to: issued) ?? issued
    }

    /// Reminder times: `firstDay` at `hour`:00, then every 7 days, keeping
    /// only those after `now`, at most `limit` of them.
    static func weeklyReminders(startingOn firstDay: Date, hour: Int, after now: Date, limit: Int, calendar: Calendar) -> [Date] {
        guard limit > 0,
              let first = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: firstDay)) else { return [] }
        var dates: [Date] = []
        var week = 0
        if first <= now {
            // Skip whole weeks already past instead of stepping through them.
            let days = calendar.dateComponents([.day], from: first, to: now).day ?? 0
            week = days / 7
        }
        while dates.count < limit, week < 10_000 {
            if let candidate = calendar.date(byAdding: .day, value: week * 7, to: first), candidate > now {
                dates.append(candidate)
            }
            week += 1
        }
        return dates
    }

    /// Past its due date and not paid.
    static func isOverdue(dueOn: Date?, paidOn: Date?, now: Date, calendar: Calendar) -> Bool {
        guard paidOn == nil, let dueOn else { return false }
        return calendar.startOfDay(for: dueOn) < calendar.startOfDay(for: now)
    }

    private static func ceilDiv(_ numerator: Int, _ denominator: Int) -> Int {
        if numerator >= 0 { return (numerator + denominator - 1) / denominator }
        return -((-numerator) / denominator)
    }
}
