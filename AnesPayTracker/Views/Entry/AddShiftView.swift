import SwiftUI
import SwiftData

// MARK: - Add / Edit Shift View

struct AddShiftView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Site.name) private var allSites: [Site]
    
    var editingShift: Shift? = nil
    
    // Form state
    @State private var selectedSite: Site?
    @State private var date: Date = Date()
    @State private var dayFraction: DayFraction = .full
    @State private var hoursWorked: Double = 8.0
    @State private var hasSplash: Bool = false
    @State private var splashAmount: Decimal = 0
    @State private var hasBonusSplash: Bool = false
    @State private var bonusSplashAmount: Decimal = 0
    @State private var customBonuses: [DraftAppliedCustomBonus] = []
    @State private var notes: String = ""
    @State private var showNotes: Bool = false
    @State private var hasSourceNote: Bool = false
    @State private var sourceContactName: String = ""
    @State private var sourceContactedOn: Date = Date()
    @State private var sourceChannel: SourceNote.ContactChannel = .text
    @State private var showStreakAlert: Bool = false
    @State private var streakAlertText: String = ""
    @State private var isSaving: Bool = false
    
    // Recently used sites (last 5 unique)
    private var recentSites: [Site] {
        let sorted = allSites.sorted {
            let aDate = $0.shifts.map(\.date).max() ?? .distantPast
            let bDate = $1.shifts.map(\.date).max() ?? .distantPast
            return aDate > bDate
        }
        return Array(sorted.prefix(5))
    }
    
    private var remainingSites: [Site] {
        let recentIDs = Set(recentSites.map(\.id))
        return allSites.filter { !recentIDs.contains($0.id) }
    }
    
    private var payUnit: PayUnit { selectedSite?.payUnit ?? .perDay }
    
    private var computedBase: Decimal {
        guard let site = selectedSite else { return 0 }
        switch payUnit {
        case .perDay: return site.baseAmount * (dayFraction.multiplier)
        case .perHour: return site.baseAmount * Decimal(hoursWorked)
        }
    }
    
    private var computedTotal: Decimal {
        computedBase
        + (hasSplash ? splashAmount : 0)
        + (hasBonusSplash ? bonusSplashAmount : 0)
        + customBonuses.filter(\.isEnabled).reduce(Decimal(0)) { $0 + $1.totalAmount }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Pay preview banner
                    if selectedSite != nil {
                        PayPreviewBanner(
                            base: computedBase,
                            splash: hasSplash ? splashAmount : 0,
                            bonusSplash: hasBonusSplash ? bonusSplashAmount : 0
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    VStack(spacing: 24) {
                        // Site picker
                        SitePickerSection(
                            selectedSite: $selectedSite,
                            recentSites: recentSites,
                            remainingSites: remainingSites
                        )
                        
                        if selectedSite != nil {
                            // Date
                            DatePickerRow(date: $date)
                            
                            Divider()
                            
                            // Duration
                            if payUnit == .perDay {
                                DayFractionPicker(selection: $dayFraction)
                            } else {
                                HoursEntry(hoursWorked: $hoursWorked)
                            }
                            
                            Divider()
                            
                            // Splash
                            SplashSection(
                                hasSplash: $hasSplash,
                                splashAmount: $splashAmount,
                                hasBonusSplash: $hasBonusSplash,
                                bonusSplashAmount: $bonusSplashAmount,
                                defaultSplash: selectedSite?.defaultSplashAmount
                            )
                            
                            if !customBonuses.isEmpty {
                                Divider()
                                CustomBonusesSection(customBonuses: $customBonuses)
                            }
                            
                            Divider()
                            
                            // Notes
                            ExpandableSection(
                                label: "Notes",
                                isExpanded: $showNotes
                            ) {
                                TextEditor(text: $notes)
                                    .frame(height: 80)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                            }
                            
                            // Source note
                            ExpandableSection(
                                label: "Source Note",
                                isExpanded: $hasSourceNote
                            ) {
                                SourceNoteFields(
                                    contactName: $sourceContactName,
                                    contactedOn: $sourceContactedOn,
                                    channel: $sourceChannel
                                )
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 96)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(CatalystFriendlyScrollDismiss())
            .navigationTitle(editingShift == nil ? "Add Shift" : "Edit Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ModalSaveButton(
                        title: editingShift == nil ? "Save" : "Update",
                        isDisabled: selectedSite == nil || isSaving
                    ) {
                        saveShift()
                    }
                }
            }
            .alert("🎯 Streak Bonus!", isPresented: $showStreakAlert) {
                Button("Great!") { dismiss() }
            } message: {
                Text(streakAlertText)
            }
        }
        .onAppear {
            populateIfEditing()
            syncCustomBonusesForSelectedSite()
        }
        .onChange(of: selectedSite?.id) { _, _ in
            syncCustomBonusesForSelectedSite()
        }
    }
    
    // MARK: - Save
    
    private func saveShift() {
        guard let site = selectedSite else { return }
        isSaving = true
        
        let shift: Shift
        if let existing = editingShift {
            // Record edit history
            let summary = buildEditSummary(existing)
            existing.editHistory.append(EditRecord(editedAt: Date(), summary: summary))
            existing.lastEditedAt = Date()
            shift = existing
        } else {
            shift = Shift()
            modelContext.insert(shift)
        }
        
        shift.site = site
        shift.date = date
        shift.payUnit = site.payUnit
        shift.dayFraction = site.payUnit == .perDay ? dayFraction : nil
        shift.hoursWorked = site.payUnit == .perHour ? hoursWorked : nil
        shift.baseAmount = site.baseAmount
        shift.splashAmount = hasSplash ? splashAmount : nil
        shift.bonusSplashAmount = hasBonusSplash ? bonusSplashAmount : nil
        shift.customBonuses = customBonuses
            .filter { $0.isEnabled && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { AppliedCustomBonus(name: $0.name, payUnit: $0.payUnit, amount: $0.amount, quantity: $0.quantity) }
        
        if hasSourceNote && !sourceContactName.isEmpty {
            shift.sourceNote = SourceNote(
                contactName: sourceContactName,
                contactedOn: sourceContactedOn,
                channel: sourceChannel
            )
        } else {
            shift.sourceNote = nil
        }
        shift.notes = notes.isEmpty ? nil : notes
        
        // Recompute streaks for employer
        if let employer = site.employer {
            StreakEngine.recomputeStreaks(for: employer)
        }
        
        // Calendar sync
        let calSync = CalendarSyncManager.shared
        if calSync.isOptedIn {
            if editingShift != nil {
                calSync.updateEvent(for: shift)
            } else {
                shift.calendarEventID = calSync.addEvent(for: shift)
            }
        }
        
        try? modelContext.save()
        
        // Check streak trigger
        if let bonus = shift.streakBonusAmount, bonus > 0, editingShift == nil {
            streakAlertText = "This shift triggered a streak bonus of \(bonus.formatted(.currency(code: "USD")))! It's been added to your total."
            showStreakAlert = true
        } else {
            dismiss()
        }
    }
    

    private func syncCustomBonusesForSelectedSite() {
        guard let bonusTypes = selectedSite?.employer?.customBonusTypes else { return }
        for bonusType in bonusTypes where !customBonuses.contains(where: { $0.sourceID == bonusType.id }) {
            customBonuses.append(DraftAppliedCustomBonus(
                sourceID: bonusType.id,
                name: bonusType.name,
                payUnit: bonusType.payUnit,
                amount: bonusType.defaultAmount,
                quantity: bonusType.payUnit == .perHour ? hoursWorked : 1,
                isEnabled: false
            ))
        }
        let validIDs = Set(bonusTypes.map(\.id))
        customBonuses.removeAll { draft in
            if let sourceID = draft.sourceID {
                return !validIDs.contains(sourceID)
            }
            return false
        }
    }
    
    private func buildEditSummary(_ shift: Shift) -> String {
        var changes: [String] = []
        if shift.date != date { changes.append("date changed") }
        if shift.dayFraction != dayFraction && payUnit == .perDay { changes.append("fraction changed to \(dayFraction.label)") }
        if shift.hoursWorked != hoursWorked && payUnit == .perHour { changes.append("hours changed to \(hoursWorked)") }
        return changes.isEmpty ? "Minor edit" : changes.joined(separator: ", ")
    }
    
    private func populateIfEditing() {
        guard let shift = editingShift else { return }
        selectedSite = shift.site
        date = shift.date
        dayFraction = shift.dayFraction ?? .full
        hoursWorked = shift.hoursWorked ?? 8.0
        hasSplash = shift.splashAmount != nil
        splashAmount = shift.splashAmount ?? 0
        hasBonusSplash = shift.bonusSplashAmount != nil
        bonusSplashAmount = shift.bonusSplashAmount ?? 0
        customBonuses = (shift.customBonuses ?? []).map { DraftAppliedCustomBonus(applied: $0) }
        syncCustomBonusesForSelectedSite()
        notes = shift.notes ?? ""
        showNotes = !notes.isEmpty
        if let sn = shift.sourceNote {
            hasSourceNote = true
            sourceContactName = sn.contactName
            sourceContactedOn = sn.contactedOn
            sourceChannel = sn.channel
        }
    }
}

// MARK: - Pay Preview Banner

struct PayPreviewBanner: View {
    let base: Decimal
    let splash: Decimal
    let bonusSplash: Decimal
    
    var total: Decimal { base + splash + bonusSplash }
    
    var body: some View {
        VStack(spacing: 6) {
            Text(total.formatted(.currency(code: "USD")))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accent)
            
            HStack(spacing: 16) {
                if base > 0 {
                    MiniPayItem(label: "Base", amount: base)
                }
                if splash > 0 {
                    MiniPayItem(label: "Splash", amount: splash)
                }
                if bonusSplash > 0 {
                    MiniPayItem(label: "Bonus", amount: bonusSplash)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.accent.opacity(0.07))
    }
}

struct MiniPayItem: View {
    let label: String
    let amount: Decimal
    var body: some View {
        VStack(spacing: 1) {
            Text(label).textCase(.uppercase).tracking(0.5)
            Text(amount.formatted(.currency(code: "USD"))).bold()
        }
    }
}

// MARK: - Site Picker

struct SitePickerSection: View {
    @Binding var selectedSite: Site?
    let recentSites: [Site]
    let remainingSites: [Site]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Site")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            if !recentSites.isEmpty {
                Text("Recent").font(.caption).foregroundStyle(.tertiary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(recentSites) { site in
                        SiteTile(site: site, isSelected: selectedSite?.id == site.id) {
                            selectedSite = site
                        }
                    }
                }
            }
            
            if !remainingSites.isEmpty {
                if !recentSites.isEmpty {
                    Text("All Sites").font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(remainingSites) { site in
                        SiteTile(site: site, isSelected: selectedSite?.id == site.id) {
                            selectedSite = site
                        }
                    }
                }
            }
        }
    }
}

struct SiteTile: View {
    let site: Site
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(site.initials)
                    .font(.title2.bold())
                    .foregroundStyle(isSelected ? .white : Color.accent)
                Text(site.name)
                    .font(.footnote.bold())
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(site.employer?.name ?? "")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(isSelected ? Color.accent : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day Fraction Picker

struct DayFractionPicker: View {
    @Binding var selection: DayFraction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day Fraction")
                .font(.subheadline).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.5)
            
            HStack(spacing: 10) {
                ForEach(DayFraction.allCases, id: \.self) { fraction in
                    Button {
                        selection = fraction
                    } label: {
                        Text(fraction.label)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(selection == fraction ? Color.accent : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(selection == fraction ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fraction.accessibilityLabel)
                }
            }
        }
    }
}

// MARK: - Hours Entry

struct HoursEntry: View {
    @Binding var hoursWorked: Double
    @State private var rawText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hours Worked")
                .font(.subheadline).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.5)
            
            HStack(spacing: 16) {
                Button {
                    hoursWorked = max(0.25, hoursWorked - 0.25)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease hours")
                
                Text(hoursWorked.formatted())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .frame(minWidth: 80)
                    .multilineTextAlignment(.center)
                
                Button {
                    hoursWorked += 0.25
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase hours")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Date Picker Row

struct DatePickerRow: View {
    @Binding var date: Date
    
    var body: some View {
        HStack {
            Text("Date")
                .font(.subheadline).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.5)
            Spacer()
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .font(.title3)
        }
    }
}


struct DraftAppliedCustomBonus: Identifiable {
    var id = UUID()
    var sourceID: UUID?
    var name: String
    var payUnit: PayUnit
    var amount: Decimal
    var quantity: Double
    var isEnabled: Bool
    
    init(sourceID: UUID?, name: String, payUnit: PayUnit, amount: Decimal, quantity: Double, isEnabled: Bool) {
        self.sourceID = sourceID
        self.name = name
        self.payUnit = payUnit
        self.amount = amount
        self.quantity = quantity
        self.isEnabled = isEnabled
    }
    
    init(applied: AppliedCustomBonus) {
        self.sourceID = nil
        self.name = applied.name
        self.payUnit = applied.payUnit
        self.amount = applied.amount
        self.quantity = applied.quantity
        self.isEnabled = true
    }
    
    var totalAmount: Decimal { amount * Decimal(quantity) }
}

struct CustomBonusesSection: View {
    @Binding var customBonuses: [DraftAppliedCustomBonus]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Bonuses")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            ForEach($customBonuses) { $bonus in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bonus.name).font(.body.bold())
                            Text(bonus.payUnit == .perHour ? "Per-hour custom bonus" : "Flat / per-day custom bonus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $bonus.isEnabled)
                    }
                    
                    if bonus.isEnabled {
                        CurrencyField(value: $bonus.amount, placeholder: "Amount")
                        if bonus.payUnit == .perHour {
                            Stepper("Hours: \(bonus.quantity.formatted())", value: $bonus.quantity, in: 0.25...24, step: 0.25)
                        }
                        Text("Adds \(bonus.totalAmount.formatted(.currency(code: "USD")))")
                            .font(.footnote.bold())
                            .foregroundStyle(Color.accent)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Splash Section

struct SplashSection: View {
    @Binding var hasSplash: Bool
    @Binding var splashAmount: Decimal
    @Binding var hasBonusSplash: Bool
    @Binding var bonusSplashAmount: Decimal
    let defaultSplash: Decimal?
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Splash Bonus").font(.body.bold())
                        Text("High-need day flat bonus").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { hasSplash },
                        set: { val in
                            hasSplash = val
                            if val && splashAmount == 0, let def = defaultSplash { splashAmount = def }
                        }
                    ))
                }
                
                if hasSplash {
                    CurrencyField(value: $splashAmount, placeholder: "Amount")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bonus Splash").font(.body.bold())
                        Text("Last-minute / hard-to-fill").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $hasBonusSplash)
                }
                
                if hasBonusSplash {
                    CurrencyField(value: $bonusSplashAmount, placeholder: "Amount")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let label: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(label)
                        .font(.body.bold())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Source Note Fields

struct SourceNoteFields: View {
    @Binding var contactName: String
    @Binding var contactedOn: Date
    @Binding var channel: SourceNote.ContactChannel
    
    var body: some View {
        VStack(spacing: 12) {
            TextField("Who told you (e.g. Tanya)", text: $contactName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("When").foregroundStyle(.secondary)
                Spacer()
                DatePicker("", selection: $contactedOn, displayedComponents: .date)
                    .labelsHidden()
            }
            
            HStack {
                Text("How").foregroundStyle(.secondary)
                Spacer()
                Picker("Channel", selection: $channel) {
                    ForEach(SourceNote.ContactChannel.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
