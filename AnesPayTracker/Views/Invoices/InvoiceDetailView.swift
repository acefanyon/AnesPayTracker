import SwiftUI
import SwiftData

// MARK: - Invoice Detail

/// One saved invoice: what it bills, its PDF, and delete. It shows the copy
/// made when the invoice was created, never the live shifts.
struct InvoiceDetailView: View {
    private let document: InvoiceDocument?
    private let number: String
    private let dueOn: Date?
    private let onSetPaid: (Date?) -> Void
    private let onDelete: () -> Void

    @Query private var shifts: [Shift]
    @AppStorage(InvoiceSettingsKey.tracksPayments) private var tracksPayments = false

    @State private var paidOn: Date?
    @State private var previewItem: PDFPreviewItem?
    @State private var showDeleteConfirm = false
    @State private var showPDFError = false

    /// Copies what it needs out of the invoice up front, so the screen never
    /// reads a record that has just been deleted.
    init(invoice: Invoice, onSetPaid: @escaping (Date?) -> Void, onDelete: @escaping () -> Void) {
        self.document = InvoiceDocument(invoice: invoice)
        self.number = invoice.number
        self.dueOn = invoice.dueOn
        self.onSetPaid = onSetPaid
        self.onDelete = onDelete
        _paidOn = State(initialValue: invoice.paidOn)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if tracksPayments {
                    paymentCard
                }

                if let document {
                    content(document)
                } else {
                    InfoCard(title: "Invoice \(number)") {
                        Text("This invoice's contents could not be read. You can delete it and create it again; your shifts are not affected.")
                            .font(.subheadline)
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Invoice", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .navigationTitle(number)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(url: item.url)
        }
        .confirmationDialog("Delete invoice \(number)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Invoice", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your shifts are not changed, and they can be put on a new invoice.")
        }
        .alert("The PDF could not be made", isPresented: $showPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    // MARK: Payment

    private var paymentCard: some View {
        InfoCard(title: "Payment") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { paidOn != nil },
                    set: { isPaid in
                        paidOn = isPaid ? Calendar.current.startOfDay(for: Date()) : nil
                        onSetPaid(paidOn)
                    }
                )) {
                    InvoicePaymentBadge(dueOn: dueOn, paidOn: paidOn)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("invoice.paidToggle")

                if let current = paidOn {
                    DatePicker("Paid on", selection: Binding(
                        get: { current },
                        set: { newDate in
                            paidOn = Calendar.current.startOfDay(for: newDate)
                            onSetPaid(paidOn)
                        }
                    ), displayedComponents: .date)
                } else {
                    Text(dueOn.map { "Due \(InvoiceFormat.day($0)). Reminders go out weekly until it's marked paid." }
                         ?? "Reminders go out weekly, starting a week after the invoice date, until it's marked paid.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ document: InvoiceDocument) -> some View {
        let snapshot = document.snapshot
        let changed = InvoiceBuilder.changedDays(in: snapshot, shifts: shifts)

        VStack(spacing: 6) {
            Text("Total due")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(InvoiceFormat.money(cents: snapshot.totalCents))
                .font(.payDisplay(size: 36))
                .foregroundStyle(Color.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        Button {
            if let url = InvoicePDFGenerator().generate(document) {
                previewItem = PDFPreviewItem(url: url)
            } else {
                showPDFError = true
            }
        } label: {
            Label("View / Share PDF", systemImage: "doc.richtext")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)

        if !changed.isEmpty {
            InfoCard(title: "Shifts changed since") {
                Label {
                    Text(changedMessage(changed))
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        InfoCard(title: "Details") {
            VStack(spacing: 0) {
                MetaRow(label: "Invoice for", value: snapshot.billToName)
                Divider()
                MetaRow(label: snapshot.siteNames.count == 1 ? "Location" : "Locations", value: snapshot.siteNames.joined(separator: ", "))
                Divider()
                MetaRow(label: "Invoice date", value: InvoiceFormat.day(document.issuedOn))
                if let dueOn = document.dueOn {
                    Divider()
                    MetaRow(label: "Due date", value: InvoiceFormat.day(dueOn))
                }
                Divider()
                MetaRow(label: "Service dates", value: InvoiceFormat.serviceDates(from: document.periodStart, to: document.periodEnd))
            }
        }

        ForEach(snapshot.days) { day in
            InvoiceDayCard(day: day)
        }

        if let notes = document.notes, !notes.isEmpty {
            InfoCard(title: "Notes") {
                Text(notes)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func changedMessage(_ changed: [InvoiceDay]) -> String {
        let dates = changed.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) }.joined(separator: ", ")
        let subject = changed.count == 1 ? "The shift on \(dates) was" : "The shifts on \(dates) were"
        return "\(subject) edited or deleted after this invoice was created. The invoice still shows what was billed. To bill the new amounts, delete this invoice and create it again."
    }
}

// MARK: - Invoice Day Card

private struct InvoiceDayCard: View {
    let day: InvoiceDay

    var body: some View {
        InfoCard(title: day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())) {
            VStack(alignment: .leading, spacing: 8) {
                if !day.siteName.isEmpty {
                    Text(day.siteName)
                        .font(.subheadline.bold())
                }

                ForEach(Array(day.caseLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label)
                        Spacer()
                        Text("\(line.startAt.formatted(date: .omitted, time: .shortened)) – \(line.endAt.formatted(date: .omitted, time: .shortened))")
                        Text(CaseTimeCalculator.durationLabel(minutes: line.minutes, compact: true))
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !day.caseLines.isEmpty { Divider() }

                ForEach(Array(day.charges.enumerated()), id: \.offset) { _, charge in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(charge.label)
                                .font(.subheadline)
                            if !charge.detail.isEmpty {
                                Text(charge.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(InvoiceFormat.money(cents: charge.amountCents))
                            .font(.subheadline)
                    }
                }

                Divider()

                HStack {
                    Text("Day total")
                    Spacer()
                    Text(InvoiceFormat.money(cents: day.totalCents))
                }
                .font(.subheadline.bold())
            }
        }
    }
}
