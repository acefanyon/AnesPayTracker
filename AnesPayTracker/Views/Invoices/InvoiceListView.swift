import SwiftUI
import SwiftData

// MARK: - Invoice List

/// Every invoice created on this device, newest first. Opened from the Report tab.
struct InvoiceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Invoice.issuedOn, order: .reverse) private var invoices: [Invoice]
    @Query private var employers: [Employer]
    @AppStorage(InvoiceSettingsKey.tracksPayments) private var tracksPayments = false

    @State private var showEditor = false
    @State private var openedInvoice: Invoice?
    @State private var pendingOpen: Invoice?
    @State private var errorMessage: String?

    /// `opening`: an invoice to show as soon as the list appears, such as one
    /// just created from a reminder on Home.
    init(opening: Invoice? = nil) {
        _pendingOpen = State(initialValue: opening)
    }

    var body: some View {
        Group {
            if invoices.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(invoices) { invoice in
                        Button {
                            openedInvoice = invoice
                        } label: {
                            InvoiceRow(invoice: invoice, showsPayment: tracksPayments)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Label("New Invoice", systemImage: "plus")
                }
                .disabled(employers.isEmpty)
            }
        }
        .sheet(isPresented: $showEditor) {
            InvoiceEditorView { created in
                openedInvoice = created
            }
        }
        .navigationDestination(item: $openedInvoice) { invoice in
            InvoiceDetailView(
                invoice: invoice,
                onSetPaid: { setPaid(invoice, on: $0) },
                onDelete: { delete(invoice) }
            )
        }
        .onAppear {
            if let pendingOpen {
                openedInvoice = pendingOpen
                self.pendingOpen = nil
            }
        }
        .alert(
            "Couldn't save the invoice",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No invoices yet", systemImage: "doc.text")
        } description: {
            Text(employers.isEmpty
                 ? "Add an employer in Settings, log some shifts, then create an invoice here."
                 : "Create one invoice per employer for the shifts you have logged. Each day lists its site, its cases with times, add-ons and a daily total.")
        } actions: {
            if !employers.isEmpty {
                Button("New Invoice") { showEditor = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Records or clears the payment date. Unpaid reminders follow on the next
    /// reschedule.
    private func setPaid(_ invoice: Invoice, on date: Date?) {
        invoice.paidOn = date
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "The payment wasn't saved. Please try again. (\(error.localizedDescription))"
        }
        Task { await InvoiceNotificationScheduler.reschedule(context: modelContext) }
    }

    /// Closes the detail screen first, so nothing is still showing the
    /// invoice when it is removed. Shifts are never touched.
    private func delete(_ invoice: Invoice) {
        openedInvoice = nil
        modelContext.delete(invoice)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "The invoice was not deleted. Please try again. (\(error.localizedDescription))"
        }
    }
}

// MARK: - Invoice Row

private struct InvoiceRow: View {
    let invoice: Invoice
    let showsPayment: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.number)
                    .font(.headline)
                Text(invoice.billToName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(InvoiceFormat.serviceDates(from: invoice.periodStart, to: invoice.periodEnd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsPayment {
                    InvoicePaymentBadge(dueOn: invoice.dueOn, paidOn: invoice.paidOn)
                }
            }
            Spacer()
            Text(InvoiceFormat.money(cents: invoice.totalCents))
                .font(.headline)
                .foregroundStyle(Color.accent)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Payment Badge

/// Paid, Unpaid or Overdue, shown when payments are tracked.
struct InvoicePaymentBadge: View {
    let dueOn: Date?
    let paidOn: Date?

    var body: some View {
        let current = status
        Label(current.text, systemImage: current.symbol)
            .font(.caption.bold())
            .foregroundStyle(current.color)
    }

    private var status: (text: String, symbol: String, color: Color) {
        if let paidOn {
            return ("Paid \(InvoiceFormat.day(paidOn))", "checkmark.circle.fill", .green)
        }
        if InvoiceScheduleMath.isOverdue(dueOn: dueOn, paidOn: paidOn, now: Date(), calendar: .current) {
            return ("Overdue", "exclamationmark.circle.fill", .red)
        }
        return ("Unpaid", "clock", .orange)
    }
}

// MARK: - Formatting

enum InvoiceFormat {
    static func money(cents: Int) -> String {
        InvoiceMath.dollars(cents: cents).formatted(.currency(code: "USD"))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func serviceDates(from start: Date, to end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) { return day(start) }
        return "\(day(start)) – \(day(end))"
    }
}
