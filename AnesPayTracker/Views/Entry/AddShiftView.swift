import SwiftUI
import SwiftData

// MARK: - Shift Draft Clipboard

struct ShiftDraftSnapshot {
    let siteID: UUID?
    let dayFraction: DayFraction?
    let hoursWorked: Double?
    let clockInAt: Date?
    let clockOutAt: Date?
    let isOnCall: Bool
    let onCallAmount: Decimal?
    let notes: String?
    let customBonuses: [AppliedCustomBonus]
    let copiedAt: Date
}

final class ShiftDraftClipboard {
    static let shared = ShiftDraftClipboard()

    private(set) var snapshot: ShiftDraftSnapshot?

    private init() {}

    var hasSnapshot: Bool { snapshot != nil }

    func copy(from shift: Shift) {
        snapshot = ShiftDraftSnapshot(
            siteID: shift.site?.id,
            dayFraction: shift.dayFraction,
            hoursWorked: shift.hoursWorked,
            clockInAt: shift.clockInAt,
            clockOutAt: shift.clockOutAt,
            isOnCall: shift.isOnCall,
            onCallAmount: shift.onCallAmount,
            notes: shift.notes,
            customBonuses: shift.customBonuses ?? [],
            copiedAt: Date()
        )
    }

    func clear() {
        snapshot = nil
    }
}

// MARK: - Add / Edit Shift View

struct AddShiftView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Site.name) private var allSites: [Site]

    var editingShift: Shift? = nil
    var initialDate: Date? = nil

    // Form state
    @State private var selectedSite: Site?
    @State private var date: Date = Date()
    @State private var dayFraction: DayFraction = .full
    @State private var hoursWorked: Double = 8.0
    @State private var usesClockTimes: Bool = false
    @State private var clockInAt: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var clockOutAt: Date = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var isOnCall: Bool = false
    @State private var onCallAmount: Decimal = 0
    @State private var customBonuses: [DraftAppliedCustomBonus] = []
    @State private var notes: String = ""
    @State private var showNotes: Bool = false
    @State private var hasSourceNote: Bool = false
    @State private var sourceContactName: String = ""
    @State private var sourceContactedOn: Date = Date()
    @State private var sourceChannel: SourceNote.ContactChannel = .text
    @State private var showStreakAlert: Bool = false
    @State private var streakAlertText: String = ""
    @State private var showPasteHint: Bool = false
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

    private var canPasteCopiedShift: Bool {
        editingShift == nil && ShiftDraftClipboard.shared.hasSnapshot
    }

    private var computedBase: Decimal {
        guard let site = selectedSite else { return 0 }
        switch payUnit {
        case .perDay: return site.baseAmount * (dayFraction.multiplier)
        case .perHour: return site.baseAmount * Decimal(hoursWorked)
        }
    }

    private var computedTotal: Decimal {
        computedBase
        + onCallPreviewPay
        + customBonuses.filter(\.isEnabled).reduce(Decimal(0)) { $0 + $1.totalAmount }
    }

    private var onCallPreviewPay: Decimal {
        isOnCall ? onCallAmount : 0
    }

    private var defaultOnCallAmount: Decimal {
        selectedSite?.employer?.defaultOnCallAmount ?? 0
    }

    private var dayFractionQuantity: Double {
        NSDecimalNumber(decimal: dayFraction.multiplier).doubleValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Pay preview banner
                    if selectedSite != nil {
                        PayPreviewBanner(
                            base: computedBase,
                            onCallBonus: onCallPreviewPay,
                            customBonus: customBonuses.filter(\.isEnabled).reduce(Decimal(0)) { $0 + $1.totalAmount }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    VStack(spacing: 24) {
                        if allSites.isEmpty {
                            NoSitesConfiguredCard()
                        }

                        if canPasteCopiedShift && showPasteHint {
                            PasteCopiedShiftCard(showPasteHint: $showPasteHint) {
                                pasteCopiedShift()
                            }
                        }

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
                                HoursEntry(
                                    hoursWorked: $hoursWorked,
                                    usesClockTimes: $usesClockTimes,
                                    clockInAt: $clockInAt,
                                    clockOutAt: $clockOutAt,
                                    serviceDate: date
                                )
                            }

                            Divider()

                            // Bonuses
                            CustomBonusesSection(
                                customBonuses: $customBonuses,
                                defaultQuantity: payUnit == .perHour ? hoursWorked : dayFractionQuantity
                            )

                            Divider()

                            OnCallSection(
                                isOnCall: $isOnCall,
                                onCallAmount: $onCallAmount,
                                employerDefaultAmount: defaultOnCallAmount
                            )

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
                    .padding(.bottom, 260)
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
            applyInitialDateIfNeeded()
            populateIfEditing()
            syncCustomBonusesForSelectedSite()
            syncOnCallForSelectedSite()
            selectDefaultSiteIfNeeded()
            showPasteHint = canPasteCopiedShift
        }
        .onChange(of: selectedSite?.id) { _, _ in
            syncCustomBonusesForSelectedSite()
            syncOnCallForSelectedSite()
        }
        .onChange(of: hoursWorked) { oldValue, newValue in
            syncPerHourCustomBonusQuantities(from: oldValue, to: newValue)
        }
        .onChange(of: clockInAt) { _, _ in syncHoursFromClockTimesIfNeeded() }
        .onChange(of: clockOutAt) { _, _ in syncHoursFromClockTimesIfNeeded() }
        .onChange(of: usesClockTimes) { _, enabled in
            if enabled { syncHoursFromClockTimesIfNeeded() }
        }
        .onChange(of: date) { _, newDate in
            clockInAt = moveClockTime(clockInAt, to: newDate)
            clockOutAt = moveClockTime(clockOutAt, to: newDate)
            syncHoursFromClockTimesIfNeeded()
        }
        .onChange(of: dayFraction) { oldValue, newValue in
            syncProratedPerDayCustomBonusQuantities(from: oldValue, to: newValue)
        }
    }

    // MARK: - Defaults / Save

    private func selectDefaultSiteIfNeeded() {
        guard editingShift == nil, selectedSite == nil else { return }
        selectedSite = recentSites.first ?? allSites.first
    }

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
        shift.clockInAt = site.payUnit == .perHour && usesClockTimes ? clockInAt : nil
        shift.clockOutAt = site.payUnit == .perHour && usesClockTimes ? clockOutAt : nil
        shift.baseAmount = site.baseAmount
        shift.isOnCall = isOnCall
        shift.onCallAmount = isOnCall ? onCallAmount : nil
        shift.splashAmount = nil
        shift.bonusSplashAmount = nil
        shift.customBonuses = customBonuses
            .filter { $0.isEnabled && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { AppliedCustomBonus(name: $0.name, payUnit: $0.payUnit, amount: $0.amount, quantity: $0.quantity, payoutSchedule: $0.payoutSchedule, proratesPartialDay: $0.proratesPartialDay) }

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
                quantity: bonusType.payUnit == .perHour ? hoursWorked : (bonusType.proratesPartialDay ? dayFractionQuantity : 1),
                payoutSchedule: bonusType.payoutSchedule,
                proratesPartialDay: bonusType.payUnit == .perDay && bonusType.proratesPartialDay,
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
        syncPerHourCustomBonusQuantities(from: hoursWorked, to: hoursWorked)
        syncProratedPerDayCustomBonusQuantities(from: dayFraction, to: dayFraction)
    }

    private func syncPerHourCustomBonusQuantities(from oldValue: Double, to newValue: Double) {
        for index in customBonuses.indices where customBonuses[index].payUnit == .perHour {
            if !customBonuses[index].isEnabled || customBonuses[index].quantity == oldValue {
                customBonuses[index].quantity = newValue
            }
        }
    }

    private func syncProratedPerDayCustomBonusQuantities(from oldValue: DayFraction, to newValue: DayFraction) {
        let oldQuantity = NSDecimalNumber(decimal: oldValue.multiplier).doubleValue
        let newQuantity = NSDecimalNumber(decimal: newValue.multiplier).doubleValue
        for index in customBonuses.indices where customBonuses[index].payUnit == .perDay && customBonuses[index].proratesPartialDay {
            if !customBonuses[index].isEnabled || customBonuses[index].quantity == oldQuantity {
                customBonuses[index].quantity = newQuantity
            }
        }
    }

    private func syncOnCallForSelectedSite() {
        guard editingShift == nil else { return }
        let employerDefaultAmount = defaultOnCallAmount
        if !isOnCall || onCallAmount == 0 {
            onCallAmount = employerDefaultAmount
        }
    }

    private func buildEditSummary(_ shift: Shift) -> String {
        var changes: [String] = []
        if shift.date != date { changes.append("date changed") }
        if shift.dayFraction != dayFraction && payUnit == .perDay { changes.append("fraction changed to \(dayFraction.label)") }
        if shift.hoursWorked != hoursWorked && payUnit == .perHour { changes.append("hours changed to \(hoursWorked)") }
        if shift.clockInAt != clockInAt && usesClockTimes { changes.append("clock-in changed") }
        if shift.clockOutAt != clockOutAt && usesClockTimes { changes.append("clock-out changed") }
        return changes.isEmpty ? "Minor edit" : changes.joined(separator: ", ")
    }

    private func applyInitialDateIfNeeded() {
        guard editingShift == nil, let initialDate else { return }
        date = initialDate
    }

    private func pasteCopiedShift() {
        guard editingShift == nil, let snapshot = ShiftDraftClipboard.shared.snapshot else { return }

        if let siteID = snapshot.siteID,
           let copiedSite = allSites.first(where: { $0.id == siteID }) {
            selectedSite = copiedSite
        }

        if let copiedDayFraction = snapshot.dayFraction {
            dayFraction = copiedDayFraction
        }

        if let copiedHours = snapshot.hoursWorked {
            hoursWorked = copiedHours
        }
        if let copiedClockIn = snapshot.clockInAt, let copiedClockOut = snapshot.clockOutAt {
            usesClockTimes = true
            clockInAt = copiedClockIn
            clockOutAt = copiedClockOut
            syncHoursFromClockTimesIfNeeded()
        }

        isOnCall = snapshot.isOnCall
        onCallAmount = snapshot.onCallAmount ?? defaultOnCallAmount

        notes = snapshot.notes ?? ""
        showNotes = !notes.isEmpty

        hasSourceNote = false
        sourceContactName = ""
        sourceContactedOn = Date()
        sourceChannel = .text

        customBonuses = copiedDraftBonuses(from: snapshot)
        syncCustomBonusesForSelectedSite()
        showPasteHint = false
    }

    private func copiedDraftBonuses(from snapshot: ShiftDraftSnapshot) -> [DraftAppliedCustomBonus] {
        let availableBonusTypes = selectedSite?.employer?.customBonusTypes ?? []

        return snapshot.customBonuses.map { applied in
            let matchingType = availableBonusTypes.first {
                $0.name == applied.name &&
                $0.payUnit == applied.payUnit &&
                $0.payoutSchedule == applied.payoutSchedule
            }

            return DraftAppliedCustomBonus(
                sourceID: matchingType?.id,
                name: applied.name,
                payUnit: applied.payUnit,
                amount: applied.amount,
                quantity: applied.quantity,
                payoutSchedule: applied.payoutSchedule,
                proratesPartialDay: applied.proratesPartialDay,
                isEnabled: true
            )
        }
    }

    private func populateIfEditing() {
        guard let shift = editingShift else { return }
        selectedSite = shift.site
        date = shift.date
        dayFraction = shift.dayFraction ?? .full
        hoursWorked = shift.hoursWorked ?? 8.0
        usesClockTimes = shift.clockInAt != nil && shift.clockOutAt != nil
        clockInAt = shift.clockInAt ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: shift.date) ?? shift.date
        clockOutAt = shift.clockOutAt ?? Calendar.current.date(byAdding: .minute, value: Int((shift.hoursWorked ?? 8.0) * 60), to: clockInAt) ?? shift.date
        isOnCall = shift.isOnCall
        onCallAmount = shift.onCallAmount ?? shift.site?.employer?.defaultOnCallAmount ?? 0
        customBonuses = (shift.customBonuses ?? []).map { DraftAppliedCustomBonus(applied: $0) }
        if let splash = shift.splashAmount, splash > 0 {
            customBonuses.append(DraftAppliedCustomBonus(sourceID: nil, name: "Splash Bonus", payUnit: .perDay, amount: splash, quantity: 1, proratesPartialDay: false, isEnabled: true))
        }
        if let bonusSplash = shift.bonusSplashAmount, bonusSplash > 0 {
            customBonuses.append(DraftAppliedCustomBonus(sourceID: nil, name: "Bonus Splash", payUnit: .perDay, amount: bonusSplash, quantity: 1, proratesPartialDay: false, isEnabled: true))
        }
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

    private func syncHoursFromClockTimesIfNeeded() {
        guard usesClockTimes else { return }
        let rounded = ClockTimeCalculator.ceilingQuarterHours(from: clockInAt, to: clockOutAt)
        let oldHours = hoursWorked
        hoursWorked = rounded
        syncPerHourCustomBonusQuantities(from: oldHours, to: rounded)
    }

    private func moveClockTime(_ clockTime: Date, to newDate: Date) -> Date {
        let cal = Calendar.current
        let timeParts = cal.dateComponents([.hour, .minute], from: clockTime)
        var dateParts = cal.dateComponents([.year, .month, .day], from: newDate)
        dateParts.hour = timeParts.hour
        dateParts.minute = timeParts.minute
        return cal.date(from: dateParts) ?? clockTime
    }
}

// MARK: - Pay Preview Banner

struct PayPreviewBanner: View {
    let base: Decimal
    let onCallBonus: Decimal
    let customBonus: Decimal

    var total: Decimal { base + onCallBonus + customBonus }

    var body: some View {
        VStack(spacing: 6) {
            Text(total.formatted(.currency(code: "USD")))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accent)

            HStack(spacing: 16) {
                if base > 0 {
                    MiniPayItem(label: "Base", amount: base)
                }
                if onCallBonus > 0 {
                    MiniPayItem(label: "On-Call", amount: onCallBonus)
                }
                if customBonus > 0 {
                    MiniPayItem(label: "Bonuses", amount: customBonus)
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

struct NoSitesConfiguredCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No sites configured", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Add an employer/site in Settings before saving a shift. Existing shifts may still appear on the calendar, but a site is required for new entries.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

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

struct ClockTimeCalculator {
    static func ceilingQuarterHours(from clockIn: Date, to clockOut: Date) -> Double {
        let minutes = max(0, clockOut.timeIntervalSince(clockIn) / 60)
        let roundedQuarterHours = ceil(minutes / 15.0) * 0.25
        return max(0.25, roundedQuarterHours)
    }
}

struct HoursEntry: View {
    @Binding var hoursWorked: Double
    @Binding var usesClockTimes: Bool
    @Binding var clockInAt: Date
    @Binding var clockOutAt: Date
    let serviceDate: Date
    @State private var rawText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hours Worked")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.5)
                Spacer()
                Toggle("Clock In/Out", isOn: $usesClockTimes)
                    .font(.footnote)
            }

            if usesClockTimes {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Clock in", selection: $clockInAt, displayedComponents: .hourAndMinute)
                    DatePicker("Clock out", selection: $clockOutAt, displayedComponents: .hourAndMinute)
                    Text("Ceiling quarter-hour rounding: any partial quarter rounds up. Example: 8.01 hours becomes 8.25.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Rounded hours: \(hoursWorked.formatted())")
                        .font(.title2.bold())
                        .foregroundStyle(Color.accent)
                }
                .onAppear { normalizeClockDatesToServiceDate() }
                .onChange(of: serviceDate) { _, _ in normalizeClockDatesToServiceDate() }
            } else {
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

    private func normalizeClockDatesToServiceDate() {
        clockInAt = combined(date: serviceDate, time: clockInAt)
        clockOutAt = combined(date: serviceDate, time: clockOutAt)
    }

    private func combined(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dateParts = cal.dateComponents([.year, .month, .day], from: date)
        let timeParts = cal.dateComponents([.hour, .minute], from: time)
        var comps = DateComponents()
        comps.year = dateParts.year
        comps.month = dateParts.month
        comps.day = dateParts.day
        comps.hour = timeParts.hour
        comps.minute = timeParts.minute
        return cal.date(from: comps) ?? time
    }
}

struct PasteCopiedShiftCard: View {
    @Binding var showPasteHint: Bool
    let onPaste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Copied shift ready")
                        .font(.headline)
                    Text("Paste the copied shift into this date. Notes copy over; source note metadata stays blank.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    onPaste()
                } label: {
                    Label("Paste Copied Shift", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if showPasteHint {
                    Button("Hide") {
                        showPasteHint = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
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


struct OnCallSection: View {
    @Binding var isOnCall: Bool
    @Binding var onCallAmount: Decimal
    let employerDefaultAmount: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("On-Call")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Toggle("", isOn: $isOnCall)
                    .labelsHidden()
                    .onChange(of: isOnCall) { _, enabled in
                        if enabled && onCallAmount == 0 {
                            onCallAmount = employerDefaultAmount
                        }
                    }
            }

            Text("Uses the employer default when first turned on. Paid with the service date, not deferred.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isOnCall {
                CurrencyField(value: $onCallAmount, placeholder: "On-call amount")
                Text("Adds \(onCallAmount.formatted(.currency(code: "USD"))) to this shift")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.accent)
            } else if employerDefaultAmount > 0 {
                Text("Default on-call amount: \(employerDefaultAmount.formatted(.currency(code: "USD")))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
    var payoutSchedule: BonusPayoutSchedule
    var proratesPartialDay: Bool
    var isEnabled: Bool

    init(sourceID: UUID?, name: String, payUnit: PayUnit, amount: Decimal, quantity: Double, payoutSchedule: BonusPayoutSchedule = .serviceDate, proratesPartialDay: Bool = false, isEnabled: Bool) {
        self.sourceID = sourceID
        self.name = name
        self.payUnit = payUnit
        self.amount = amount
        self.quantity = quantity
        self.payoutSchedule = payoutSchedule
        self.proratesPartialDay = proratesPartialDay
        self.isEnabled = isEnabled
    }

    init(applied: AppliedCustomBonus) {
        self.sourceID = nil
        self.name = applied.name
        self.payUnit = applied.payUnit
        self.amount = applied.amount
        self.quantity = applied.quantity
        self.payoutSchedule = applied.payoutSchedule
        self.proratesPartialDay = applied.proratesPartialDay
        self.isEnabled = true
    }

    var totalAmount: Decimal { amount * Decimal(quantity) }
}

struct CustomBonusesSection: View {
    @Binding var customBonuses: [DraftAppliedCustomBonus]
    let defaultQuantity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bonuses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    customBonuses.append(DraftAppliedCustomBonus(
                        sourceID: nil,
                        name: "One-time Bonus",
                        payUnit: .perDay,
                        amount: 0,
                        quantity: defaultQuantity,
                        payoutSchedule: .serviceDate,
                        proratesPartialDay: true,
                        isEnabled: true
                    ))
                } label: {
                    Label("Add One-Time Bonus", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel("Add custom bonus")
            }

            if customBonuses.isEmpty {
                Text("No saved employer bonuses yet. Use Add One-Time Bonus for a high-need or last-minute bonus on this shift.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            ForEach($customBonuses) { $bonus in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if bonus.sourceID == nil {
                                TextField("Bonus name", text: $bonus.name)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Text(bonus.name).font(.body.bold())
                            }
                            Text("\(bonus.payUnit == .perHour ? "Per-hour bonus" : "Flat / per-day bonus") · paid: \(bonus.payoutSchedule.shortLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if bonus.sourceID == nil {
                            Button(role: .destructive) {
                                customBonuses.removeAll { $0.id == bonus.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove custom bonus")
                        } else {
                            Toggle("", isOn: $bonus.isEnabled)
                        }
                    }

                    if bonus.isEnabled {
                        if bonus.sourceID == nil {
                            Picker("How this bonus pays", selection: $bonus.payUnit) {
                                Text("Flat").tag(PayUnit.perDay)
                                Text("Per Hour").tag(PayUnit.perHour)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: bonus.payUnit) { _, newUnit in
                                if newUnit == .perDay {
                                    bonus.proratesPartialDay = true
                                    bonus.quantity = defaultQuantity
                                } else {
                                    bonus.proratesPartialDay = false
                                    if bonus.quantity < 1 && defaultQuantity > 1 {
                                        bonus.quantity = defaultQuantity
                                    }
                                }
                            }
                        }
                        CurrencyField(value: $bonus.amount, placeholder: "Amount")
                        Picker("How and when paid", selection: $bonus.payoutSchedule) {
                            ForEach(BonusPayoutSchedule.allCases, id: \.self) { schedule in
                                Text(schedule.displayName).tag(schedule)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(bonus.payoutSchedule.descriptiveLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if bonus.payUnit == .perDay {
                            Toggle("Prorate for partial day", isOn: $bonus.proratesPartialDay)
                                .onChange(of: bonus.proratesPartialDay) { _, shouldProrate in
                                    bonus.quantity = shouldProrate ? defaultQuantity : 1
                                }
                            Text(bonus.proratesPartialDay ? "Uses this shift's day fraction for the bonus amount." : "Pays the full bonus amount even on a partial-day shift.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if bonus.payUnit == .perHour {
                            Stepper("Hours: \(bonus.quantity.formatted())", value: $bonus.quantity, in: 0.25...24, step: 0.25)
                                .onAppear {
                                    if bonus.quantity == 1, defaultQuantity > 1 {
                                        bonus.quantity = defaultQuantity
                                    }
                                }
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
