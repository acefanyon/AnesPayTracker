import SwiftUI
import SwiftData

// MARK: - Sender details

/// The user's own details, printed at the top of every invoice. Kept in app
/// settings on the device; each created invoice stores its own copy.
enum InvoiceSenderKey {
    static let name = "invoiceSender.name"
    static let address = "invoiceSender.address"
    static let phone = "invoiceSender.phone"
    static let email = "invoiceSender.email"
}

// MARK: - Address Fields

/// Three single-line fields for one address, which is kept as lines of text
/// and printed one line per field. (A multi-line text field can't be used:
/// the keyboard's Return key ends editing instead of starting a new line.)
private struct AddressFields: View {
    @Binding var address: String

    private static let prompts = ["Street address", "Suite or unit (optional)", "City, State ZIP"]

    var body: some View {
        ForEach(Self.prompts.indices, id: \.self) { index in
            TextField(Self.prompts[index], text: Binding(
                get: { InvoiceMath.addressFields(address)[index] },
                set: { address = InvoiceMath.address(address, settingField: index, to: $0) }
            ))
            .textInputAutocapitalization(.words)
        }
    }
}

// MARK: - Invoice Editor

/// Creates an invoice from an employer's logged shifts, across all of its sites.
struct InvoiceEditorView: View {
    let onCreated: (Invoice) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Employer.name) private var employers: [Employer]
    @Query private var invoices: [Invoice]

    @AppStorage(InvoiceSenderKey.name) private var senderName = ""
    @AppStorage(InvoiceSenderKey.address) private var senderAddress = ""
    @AppStorage(InvoiceSenderKey.phone) private var senderPhone = ""
    @AppStorage(InvoiceSenderKey.email) private var senderEmail = ""

    @State private var employerID: UUID?
    @State private var billToName = ""
    @State private var billToAddress = ""
    @State private var employerCode = ""
    @State private var periodStart = Date()
    @State private var periodEnd = Date()
    @State private var issuedOn = Date()
    @State private var hasDueDate = false
    @State private var dueOn = Date()
    @State private var excludedShiftIDs: Set<UUID> = []
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var previewItem: PDFPreviewItem?

    private let calendar = Calendar.current

    // MARK: Derived

    private struct ShiftRow: Identifiable {
        let shift: Shift
        let day: InvoiceDay
        let invoicedOn: String?

        var id: UUID { shift.id }
        var isBillable: Bool { invoicedOn == nil && day.totalCents > 0 }
    }

    private var employer: Employer? { employers.first { $0.id == employerID } }

    private var shiftRows: [ShiftRow] {
        guard let employer else { return [] }
        let invoiced = InvoiceBuilder.invoiceNumbersByShift(invoices)
        return InvoiceBuilder.candidateShifts(for: employer, from: periodStart, through: periodEnd, calendar: calendar).map {
            ShiftRow(shift: $0, day: InvoiceBuilder.day(for: $0), invoicedOn: invoiced[$0.id])
        }
    }

    private func includedRows(_ rows: [ShiftRow]) -> [ShiftRow] {
        rows.filter { $0.isBillable && !excludedShiftIDs.contains($0.id) }
    }

    private var number: String {
        InvoiceMath.uniqueNumber(
            base: InvoiceMath.invoiceNumber(employerCode: employerCode, date: issuedOn, calendar: calendar),
            existing: Set(invoices.map(\.number))
        )
    }

    /// The first thing that stops this invoice from being created, or nil.
    private func problem(_ rows: [ShiftRow]) -> String? {
        if senderName.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter your name under Your Details." }
        if employer == nil { return "Choose an employer." }
        if billToName.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter who the invoice is for." }
        if InvoiceMath.sanitizedCode(employerCode).isEmpty {
            return "Enter the employer code for the invoice number."
        }
        if calendar.startOfDay(for: periodEnd) < calendar.startOfDay(for: periodStart) {
            return "The last service date is before the first."
        }
        let included = includedRows(rows)
        if included.isEmpty { return "There are no shifts to bill in these dates." }
        if let running = included.first(where: { $0.shift.runningCase != nil }) {
            return "A case is still running on \(running.shift.date.formatted(.dateTime.month(.abbreviated).day())). Stop it before invoicing that day."
        }
        return nil
    }

    private func snapshot(_ rows: [ShiftRow]) -> InvoiceSnapshot {
        InvoiceSnapshot(
            senderName: senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            senderAddress: senderAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            senderPhone: senderPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            senderEmail: senderEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            billToName: billToName.trimmingCharacters(in: .whitespacesAndNewlines),
            billToAddress: billToAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            days: includedRows(rows).map(\.day)
        )
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Body

    var body: some View {
        let rows = shiftRows
        let currentProblem = problem(rows)

        NavigationStack {
            Form {
                senderSection
                billToSection
                datesSection
                shiftsSection(rows)
                Section("Notes (optional)") {
                    TextField("Shown at the bottom of the invoice", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                summarySection(rows, problem: currentProblem)
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(currentProblem != nil)
                }
            }
            .onAppear(perform: selectDefaultEmployerIfNeeded)
            .onChange(of: periodEnd) { _, _ in
                // Keep a shown due date in step; never switch it back on.
                if hasDueDate, let employer { updateDueDate(for: employer) }
            }
            .sheet(item: $previewItem) { item in
                PDFPreviewSheet(url: item.url)
            }
            .alert(
                "Couldn't create the invoice",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var senderSection: some View {
        Section {
            TextField("Your name, as it should appear", text: $senderName)
                .textContentType(.name)
            AddressFields(address: $senderAddress)
            TextField("Phone (optional)", text: $senderPhone)
                .keyboardType(.phonePad)
            TextField("Email (optional)", text: $senderEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Your Details")
        } footer: {
            Text("Saved on this device and reused for the next invoice.")
        }
    }

    private var billToSection: some View {
        Section {
            Picker("Employer", selection: Binding(
                get: { employerID },
                set: { newID in
                    if let picked = employers.first(where: { $0.id == newID }) { select(employer: picked) }
                }
            )) {
                ForEach(employers) { option in
                    Text(option.name).tag(Optional(option.id))
                }
            }

            TextField("Name to bill", text: $billToName)
            AddressFields(address: $billToAddress)

            LabeledContent("Employer code") {
                codeField("EN", text: $employerCode)
            }
        } header: {
            Text("Invoice For")
        } footer: {
            Text("The code and the invoice date make the invoice number, for example EN-041326. The code is saved with the employer.")
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            DatePicker("First service date", selection: $periodStart, displayedComponents: .date)
            DatePicker("Last service date", selection: $periodEnd, displayedComponents: .date)
            DatePicker("Invoice date", selection: $issuedOn, displayedComponents: .date)
            Toggle("Show a due date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due date", selection: $dueOn, displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private func shiftsSection(_ rows: [ShiftRow]) -> some View {
        Section {
            if rows.isEmpty {
                Text(employer == nil ? "Choose an employer." : "No shifts for this employer in these dates.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                if row.isBillable {
                    Toggle(isOn: Binding(
                        get: { !excludedShiftIDs.contains(row.id) },
                        set: { isIncluded in
                            if isIncluded {
                                excludedShiftIDs.remove(row.id)
                            } else {
                                excludedShiftIDs.insert(row.id)
                            }
                        }
                    )) {
                        shiftLabel(row)
                    }
                } else {
                    shiftLabel(row)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Shifts")
        } footer: {
            Text("Shifts at all of this employer's sites. Each day shows its site, its cases with times, then add-ons and a daily total. Streak bonuses are not invoiced.")
        }
    }

    private func shiftLabel(_ row: ShiftRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.shift.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                Spacer()
                Text(InvoiceMath.dollars(cents: row.day.totalCents).formatted(.currency(code: "USD")))
            }
            Text(detail(for: row))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detail(for row: ShiftRow) -> String {
        let status = status(for: row)
        return row.day.siteName.isEmpty ? status : "\(row.day.siteName) · \(status)"
    }

    private func status(for row: ShiftRow) -> String {
        if let invoicedOn = row.invoicedOn { return "Already on invoice \(invoicedOn)" }
        if row.day.totalCents == 0 { return "Nothing to bill yet" }
        if row.shift.runningCase != nil { return "A case is still running" }
        if row.shift.isCaseTracked {
            let count = row.day.caseLines.count
            return "\(count) case\(count == 1 ? "" : "s") · \(CaseTimeCalculator.durationLabel(minutes: row.shift.caseMinutes))"
        }
        switch row.shift.payUnit {
        case .perDay:
            let fraction = row.shift.dayFraction ?? .full
            return fraction == .full ? "Full day" : "\(fraction.label) day"
        case .perHour:
            return row.shift.hoursLabel
        }
    }

    @ViewBuilder
    private func summarySection(_ rows: [ShiftRow], problem: String?) -> some View {
        let included = includedRows(rows)
        let totalCents = included.reduce(0) { $0 + $1.day.totalCents }
        Section {
            LabeledContent("Invoice number", value: number)
            LabeledContent("Days billed", value: "\(included.count)")
            LabeledContent("Total") {
                Text(InvoiceMath.dollars(cents: totalCents).formatted(.currency(code: "USD")))
                    .bold()
                    .foregroundStyle(Color.accent)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Button {
                    preview(rows)
                } label: {
                    Label("Preview PDF", systemImage: "doc.viewfinder")
                }
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("Once created, an invoice keeps its contents even if the shifts are edited later.")
        }
    }

    private func codeField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = InvoiceMath.sanitizedCode($0) }
        ))
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 80)
    }

    // MARK: Actions

    private func selectDefaultEmployerIfNeeded() {
        guard employerID == nil else { return }
        if let first = employers.first(where: { !$0.caseTimeSites.isEmpty }) ?? employers.first {
            select(employer: first)
        }
    }

    private func select(employer: Employer) {
        employerID = employer.id
        billToName = employer.billingName ?? employer.name
        billToAddress = employer.billingAddress ?? ""
        employerCode = employer.invoiceCode ?? InvoiceMath.suggestedCode(from: employer.name)
        excludedShiftIDs = []

        // Default to what hasn't been invoiced yet for this employer, going
        // back to the start of last month so a long history isn't all listed.
        let today = Date()
        let invoiced = InvoiceBuilder.invoiceNumbersByShift(invoices)
        let endOfToday = calendar.endOfDay(for: today)
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let earliest = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let unbilledDates = employer.sites
            .flatMap(\.shifts)
            .filter { invoiced[$0.id] == nil && $0.date >= earliest && $0.date <= endOfToday }
            .map(\.date)
        periodStart = unbilledDates.min() ?? today
        periodEnd = today
        hasDueDate = employer.hasPaycheckAnchors
        updateDueDate(for: employer)
    }

    /// Suggests the payday for the last service date when the employer's paydays are known.
    private func updateDueDate(for employer: Employer) {
        guard employer.hasPaycheckAnchors else { return }
        dueOn = StreakEngine.paycheckDate(for: periodEnd, employer: employer)
    }

    private func document(_ rows: [ShiftRow]) -> InvoiceDocument {
        InvoiceDocument(
            number: number,
            issuedOn: issuedOn,
            dueOn: hasDueDate ? dueOn : nil,
            periodStart: periodStart,
            periodEnd: periodEnd,
            notes: trimmedNotes,
            snapshot: snapshot(rows)
        )
    }

    private func preview(_ rows: [ShiftRow]) {
        if let url = InvoicePDFGenerator().generate(document(rows)) {
            previewItem = PDFPreviewItem(url: url)
        } else {
            errorMessage = "The PDF could not be made. Please try again."
        }
    }

    private func create() {
        let rows = shiftRows
        guard let employer, problem(rows) == nil else { return }
        do {
            let invoice = try InvoiceBuilder.makeInvoice(
                number: number,
                employer: employer,
                periodStart: periodStart,
                periodEnd: periodEnd,
                issuedOn: issuedOn,
                dueOn: hasDueDate ? dueOn : nil,
                notes: trimmedNotes,
                snapshot: snapshot(rows)
            )
            let trimmedAddress = billToAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            employer.invoiceCode = InvoiceMath.sanitizedCode(employerCode)
            employer.billingName = billToName.trimmingCharacters(in: .whitespacesAndNewlines)
            employer.billingAddress = trimmedAddress.isEmpty ? nil : trimmedAddress
            modelContext.insert(invoice)
            try modelContext.save()
            dismiss()
            onCreated(invoice)
        } catch {
            errorMessage = "Nothing was saved. Please try again. (\(error.localizedDescription))"
        }
    }
}
