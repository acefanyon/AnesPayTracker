import SwiftUI
import SwiftData

// MARK: - Invoice Home Cards

/// Home's invoice cards: periods that need an invoice, and (when payments are
/// tracked) invoices not yet paid. Shows nothing when there is nothing to do.
/// Reads only; creating an invoice happens in `InvoiceEditorView`.
struct InvoiceHomeCards: View {
    @Query(sort: \Employer.name) private var employers: [Employer]
    @Query private var invoices: [Invoice]
    @AppStorage(InvoiceSettingsKey.tracksPayments) private var tracksPayments = false

    @State private var prefill: InvoicePrefill?
    @State private var createdInvoice: Invoice?

    var body: some View {
        let now = Date()
        let due = InvoiceReminders.duePeriods(employers: employers, invoices: invoices, now: now)
        let unpaid = tracksPayments ? InvoiceReminders.unpaidInvoices(invoices) : []

        VStack(alignment: .leading, spacing: 12) {
            if !due.isEmpty {
                InvoicesDueCard(due: due, showEmployerName: employers.count > 1) { entry in
                    prefill = InvoicePrefill(employerID: entry.employer.id, period: entry.period)
                }
            }
            if !unpaid.isEmpty {
                UnpaidInvoicesCard(unpaid: unpaid, now: now)
            }
        }
        .sheet(item: $prefill) { prefill in
            InvoiceEditorView(prefill: prefill) { created in
                createdInvoice = created
            }
        }
        // Open the new invoice so its PDF can be shared straight away.
        .navigationDestination(item: $createdInvoice) { invoice in
            InvoiceListView(opening: invoice)
        }
    }
}

// MARK: - Invoices Due

private struct InvoicesDueCard: View {
    let due: [InvoiceDuePeriod]
    let showEmployerName: Bool
    let onCreate: (InvoiceDuePeriod) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(due.count == 1 ? "Invoice due" : "\(due.count) invoices due", systemImage: "doc.badge.clock")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(due) { entry in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.employer.name)
                            .font(.subheadline.bold())
                        Text("\(InvoiceReminders.periodLabel(entry.period)) · \(entry.shiftCount) shift\(entry.shiftCount == 1 ? "" : "s") · \(InvoiceFormat.money(cents: entry.totalCents))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Create") { onCreate(entry) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Create invoice for \(entry.employer.name), \(InvoiceReminders.periodLabel(entry.period))")
                        .accessibilityIdentifier("invoiceDue.create")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Unpaid Invoices

private struct UnpaidInvoicesCard: View {
    let unpaid: [Invoice]
    let now: Date

    private var overdueCount: Int {
        unpaid.filter { InvoiceScheduleMath.isOverdue(dueOn: $0.dueOn, paidOn: $0.paidOn, now: now, calendar: .current) }.count
    }

    var body: some View {
        NavigationLink {
            InvoiceListView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(overdueCount > 0 ? .red : Color.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unpaid.count == 1 ? "1 invoice not paid yet" : "\(unpaid.count) invoices not paid yet")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(minHeight: 44)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("invoices.unpaidCard")
    }

    private var subtitle: String {
        let total = InvoiceFormat.money(cents: unpaid.reduce(0) { $0 + $1.totalCents })
        return overdueCount > 0 ? "\(total) · \(overdueCount) overdue" : total
    }
}
