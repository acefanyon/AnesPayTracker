import SwiftUI
import SwiftData
import UIKit

// MARK: - Invoice Settings

/// Settings → Invoices: payment tracking (app-wide) and invoice reminders
/// (per employer).
struct InvoiceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employer.name) private var employers: [Employer]
    @Query private var invoices: [Invoice]
    @AppStorage(InvoiceSettingsKey.tracksPayments) private var tracksPayments = false

    @State private var notificationsDenied = false
    @State private var showMarkExistingPaid = false
    @State private var errorMessage: String?

    private var unpaidCount: Int { invoices.filter { $0.paidOn == nil }.count }

    var body: some View {
        List {
            if notificationsDenied {
                Section {
                    Label("Notifications are off for AnesPay, so reminders only appear on Home.", systemImage: "bell.slash")
                        .font(.subheadline)
                    Button("Open Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section {
                ForEach(employers) { employer in
                    NavigationLink {
                        EmployerInvoiceReminderView(employer: employer)
                    } label: {
                        LabeledContent(employer.name, value: employer.invoiceCadence?.displayName ?? "Off")
                    }
                }
            } header: {
                Text("Invoice Reminders")
            } footer: {
                Text("When a period ends with shifts that aren't on an invoice, Home shows it as due and AnesPay reminds you at 9 AM the next day, then weekly until you create the invoice.")
            }

            Section {
                Toggle("Track invoice payments", isOn: Binding(
                    get: { tracksPayments },
                    set: { setTracksPayments($0) }
                ))
            } header: {
                Text("Payments")
            } footer: {
                Text("Mark each invoice paid when the money arrives. Unpaid invoices are reminded weekly, starting on the due date, or a week after the invoice date if there isn't one.")
            }
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .task { notificationsDenied = await InvoiceNotificationScheduler.isDenied() }
        .confirmationDialog(
            "Mark existing invoices as paid?",
            isPresented: $showMarkExistingPaid,
            titleVisibility: .visible
        ) {
            Button("Mark \(unpaidCount) as Paid Today") { markExistingPaid() }
            Button("Leave Them Unpaid", role: .cancel) {}
        } message: {
            Text("You already have \(unpaidCount) invoice\(unpaidCount == 1 ? "" : "s"). Unpaid invoices get weekly reminders. You can change each paid date on the invoice.")
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func setTracksPayments(_ isOn: Bool) {
        tracksPayments = isOn
        if isOn && unpaidCount > 0 { showMarkExistingPaid = true }
        Task {
            if isOn { _ = await InvoiceNotificationScheduler.requestAuthorization() }
            notificationsDenied = await InvoiceNotificationScheduler.isDenied()
            await InvoiceNotificationScheduler.reschedule(context: modelContext)
        }
    }

    private func markExistingPaid() {
        let today = Date()
        for invoice in invoices where invoice.paidOn == nil {
            invoice.paidOn = today
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "Nothing was changed. Please try again. (\(error.localizedDescription))"
        }
        Task { await InvoiceNotificationScheduler.reschedule(context: modelContext) }
    }
}

// MARK: - Employer Invoice Reminder

/// How often one employer is invoiced, and from when reminders start.
struct EmployerInvoiceReminderView: View {
    let employer: Employer

    @Environment(\.modelContext) private var modelContext

    @State private var cadence: InvoiceCadence?
    @State private var anchor = Date()
    @State private var startDate = Date()
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    /// "Each pay period" is offered only when the pay periods are real dates.
    private var options: [InvoiceCadence] {
        InvoiceCadence.allCases.filter { $0 != .payPeriod || employer.hasReliablePayPeriods || cadence == .payPeriod }
    }

    var body: some View {
        Form {
            Section {
                Picker("Remind me to invoice", selection: Binding(
                    get: { cadence },
                    set: { changeCadence(to: $0) }
                )) {
                    Text("Off").tag(InvoiceCadence?.none)
                    ForEach(options) { option in
                        Text(option.displayName).tag(Optional(option))
                    }
                }
            } footer: {
                if cadence == .payPeriod {
                    Text("Uses \(employer.name)'s pay periods from its pay schedule.")
                }
            }

            if let cadence {
                if cadence.needsAnchor {
                    Section {
                        DatePicker("A period ends on", selection: Binding(
                            get: { anchor },
                            set: { anchor = $0; save() }
                        ), displayedComponents: .date)
                    } footer: {
                        Text("Pick the last day of any one period, past or future. The others follow every \(cadence == .weekly ? "week" : "2 weeks") from it.")
                    }
                }

                Section {
                    DatePicker("Remind about shifts from", selection: Binding(
                        get: { startDate },
                        set: { startDate = $0; save() }
                    ), displayedComponents: .date)
                    if let current = InvoiceReminders.period(containing: Date(), for: employer, calendar: calendar) {
                        LabeledContent("Current period", value: InvoiceReminders.periodLabel(current))
                    }
                } footer: {
                    Text("Shifts in earlier periods are left out, so turning reminders on doesn't flag work you've already invoiced elsewhere.")
                }
            }
        }
        .navigationTitle(employer.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        cadence = employer.invoiceCadence
        anchor = employer.invoicePeriodEndAnchor ?? employer.payPeriodEndAnchorDate ?? Date()
        startDate = employer.invoiceRemindersStartDate ?? Date()
    }

    private func changeCadence(to newValue: InvoiceCadence?) {
        let wasOff = cadence == nil
        cadence = newValue
        if wasOff && newValue != nil && employer.invoiceRemindersStartDate == nil {
            startDate = Date()
        }
        save()
        if newValue != nil {
            Task { _ = await InvoiceNotificationScheduler.requestAuthorization() }
        }
    }

    private func save() {
        employer.invoiceCadence = cadence
        employer.invoicePeriodEndAnchor = cadence?.needsAnchor == true ? calendar.startOfDay(for: anchor) : employer.invoicePeriodEndAnchor
        employer.invoiceRemindersStartDate = cadence == nil ? employer.invoiceRemindersStartDate : calendar.startOfDay(for: startDate)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            hasLoaded = false
            load()
            errorMessage = "The reminder setting wasn't saved. Please try again. (\(error.localizedDescription))"
            return
        }
        Task { await InvoiceNotificationScheduler.reschedule(context: modelContext) }
    }
}
