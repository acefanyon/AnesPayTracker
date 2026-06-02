import SwiftUI
import SwiftData

// MARK: - Employer Setup Wizard

enum EmployerWizardMode: Equatable {
    case create
    case edit
    case duplicateVersion

    var navigationTitle: String {
        switch self {
        case .create:
            return "Add Employer"
        case .edit:
            return "Edit Employer"
        case .duplicateVersion:
            return "New Employer Version"
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .create:
            return "Save Employer"
        case .edit:
            return "Save Changes"
        case .duplicateVersion:
            return "Create Version"
        }
    }
}

struct EmployerSetupWizard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: EmployerWizardMode
    let sourceEmployer: Employer?

    @State private var step: WizardStep = .employerInfo
    @State private var employerName: String
    @State private var payCadence: PayCadence
    @State private var customCadenceDays: Int
    @State private var defaultOnCallAmount: Decimal
    @State private var contactPersons: [DraftContact]
    @State private var sites: [DraftSite]
    @State private var streakRules: [DraftStreakRule]
    @State private var customBonusTypes: [DraftCustomBonusType]

    init(mode: EmployerWizardMode = .create, sourceEmployer: Employer? = nil) {
        self.mode = mode
        self.sourceEmployer = sourceEmployer

        let name: String
        if mode == .duplicateVersion, let sourceEmployer {
            name = EmployerSetupWizard.nextEmployerVersionName(from: sourceEmployer.name)
        } else {
            name = sourceEmployer?.name ?? ""
        }

        _employerName = State(initialValue: name)
        _payCadence = State(initialValue: sourceEmployer?.payCadence ?? .biweekly)
        _customCadenceDays = State(initialValue: sourceEmployer?.customCadenceDays ?? 14)
        _defaultOnCallAmount = State(initialValue: sourceEmployer?.defaultOnCallAmount ?? 0)
        _contactPersons = State(initialValue: sourceEmployer?.contactPersons.map { DraftContact(contact: $0) } ?? [])

        let seededSites = sourceEmployer?.sites.sorted { $0.createdAt < $1.createdAt }.map { DraftSite(site: $0) } ?? [DraftSite()]
        _sites = State(initialValue: seededSites.isEmpty ? [DraftSite()] : seededSites)

        _streakRules = State(initialValue: sourceEmployer?.streakRules.sorted { $0.createdAt < $1.createdAt }.map { DraftStreakRule(rule: $0) } ?? [])
        _customBonusTypes = State(initialValue: sourceEmployer?.customBonusTypes.sorted { $0.createdAt < $1.createdAt }.map { DraftCustomBonusType(bonus: $0) } ?? [])
    }

    private var isEditingExistingEmployer: Bool {
        mode == .edit && sourceEmployer != nil
    }

    private var historyProtectionMessage: String {
        switch mode {
        case .create:
            return ""
        case .edit:
            return "These edits update employer defaults and setup metadata only. Saved shifts keep their own pay snapshots, and reconciled history is not recomputed automatically."
        case .duplicateVersion:
            return "This creates a second employer record prefilled from the current one so future rule changes can start fresh without touching historical shifts."
        }
    }

    enum WizardStep: Int, CaseIterable {
        case employerInfo = 0
        case sites = 1
        case customBonuses = 2
        case streakRules = 3
        case review = 4

        var title: String {
            switch self {
            case .employerInfo: return "Employer Info"
            case .sites: return "Sites & Rates"
            case .customBonuses: return "Custom Bonuses"
            case .streakRules: return "Streak Rules"
            case .review: return "Review"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("wizard-top")

                        // Progress
                        WizardProgressBar(currentStep: step.rawValue, totalSteps: WizardStep.allCases.count)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)

                        // Step title
                        Text(step.title)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        Divider()

                        VStack(spacing: 16) {
                            if !historyProtectionMessage.isEmpty {
                                Text(historyProtectionMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }

                            switch step {
                            case .employerInfo:
                                EmployerInfoStep(
                                    name: $employerName,
                                    payCadence: $payCadence,
                                    customCadenceDays: $customCadenceDays,
                                    defaultOnCallAmount: $defaultOnCallAmount,
                                    contactPersons: $contactPersons
                                )
                            case .sites:
                                SitesStep(sites: $sites, isEditingExistingEmployer: isEditingExistingEmployer)
                            case .customBonuses:
                                CustomBonusesStep(customBonusTypes: $customBonusTypes, isEditingExistingEmployer: isEditingExistingEmployer)
                            case .streakRules:
                                StreakRulesStep(rules: $streakRules, isEditingExistingEmployer: isEditingExistingEmployer)
                            case .review:
                                WizardReviewStep(
                                    mode: mode,
                                    employerName: employerName,
                                    payCadence: payCadence,
                                    defaultOnCallAmount: defaultOnCallAmount,
                                    sites: sites,
                                    streakRules: streakRules,
                                    customBonusTypes: customBonusTypes
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .padding(.bottom, 160)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(CatalystFriendlyScrollDismiss())
                .onChange(of: step) { _, _ in
                    proxy.scrollTo("wizard-top", anchor: .top)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 16) {
                        if step.rawValue > 0 {
                            Button("Back") {
                                goBack()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }

                        Spacer()

                        Button(step == .review ? mode.primaryButtonTitle : "Next") {
                            if step == .review {
                                saveEmployer()
                            } else {
                                goNext()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(step == .employerInfo && employerName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step.rawValue > 0 {
                        ModalBackButton {
                            goBack()
                        }
                    } else {
                        ModalCancelButton { dismiss() }
                    }
                }
            }
        }
    }

    private func goBack() {
        step = WizardStep(rawValue: step.rawValue - 1) ?? .employerInfo
    }

    private func goNext() {
        step = WizardStep(rawValue: step.rawValue + 1) ?? .review
    }

    private func saveEmployer() {
        switch mode {
        case .create, .duplicateVersion:
            let employer = Employer(
                name: employerName.trimmingCharacters(in: .whitespacesAndNewlines),
                payCadence: payCadence,
                customCadenceDays: payCadence == .custom ? customCadenceDays : nil,
                defaultOnCallAmount: defaultOnCallAmount
            )

            syncEmployer(employer, allowDeletes: true, insertNewObjects: true)
            modelContext.insert(employer)
        case .edit:
            guard let sourceEmployer else { return }
            syncEmployer(sourceEmployer, allowDeletes: false, insertNewObjects: true)
        }

        try? modelContext.save()
        dismiss()
    }

    private func syncEmployer(_ employer: Employer, allowDeletes: Bool, insertNewObjects: Bool) {
        employer.name = employerName.trimmingCharacters(in: .whitespacesAndNewlines)
        employer.payCadence = payCadence
        employer.customCadenceDays = payCadence == .custom ? customCadenceDays : nil
        employer.defaultOnCallAmount = defaultOnCallAmount

        syncContacts(for: employer, allowDeletes: allowDeletes, insertNewObjects: insertNewObjects)
        syncSites(for: employer, allowDeletes: allowDeletes, insertNewObjects: insertNewObjects)
        syncStreakRules(for: employer, allowDeletes: allowDeletes, insertNewObjects: insertNewObjects)
        syncCustomBonuses(for: employer, allowDeletes: allowDeletes, insertNewObjects: insertNewObjects)
    }

    private func syncContacts(for employer: Employer, allowDeletes: Bool, insertNewObjects: Bool) {
        var retainedIDs = Set<UUID>()
        var updatedContacts: [ContactPerson] = []

        for draft in contactPersons {
            let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            if let sourceID = draft.sourceID,
               let existing = employer.contactPersons.first(where: { $0.id == sourceID }) {
                existing.name = trimmedName
                existing.role = draft.trimmedRole
                retainedIDs.insert(existing.id)
                updatedContacts.append(existing)
            } else {
                let contact = ContactPerson(name: trimmedName, role: draft.trimmedRole)
                if insertNewObjects { modelContext.insert(contact) }
                retainedIDs.insert(contact.id)
                updatedContacts.append(contact)
            }
        }

        if allowDeletes {
            for contact in employer.contactPersons where !retainedIDs.contains(contact.id) {
                modelContext.delete(contact)
            }
        } else {
            for contact in employer.contactPersons where !retainedIDs.contains(contact.id) {
                updatedContacts.append(contact)
            }
        }

        employer.contactPersons = updatedContacts
    }

    private func syncSites(for employer: Employer, allowDeletes: Bool, insertNewObjects: Bool) {
        var retainedIDs = Set<UUID>()
        var updatedSites: [Site] = []

        for draft in sites {
            let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            if let sourceID = draft.sourceID,
               let existing = employer.sites.first(where: { $0.id == sourceID }) {
                existing.name = trimmedName
                existing.payUnit = draft.payUnit
                existing.baseAmount = draft.baseAmount
                retainedIDs.insert(existing.id)
                updatedSites.append(existing)
            } else {
                let site = Site(name: trimmedName, employer: employer, payUnit: draft.payUnit, baseAmount: draft.baseAmount)
                if insertNewObjects { modelContext.insert(site) }
                retainedIDs.insert(site.id)
                updatedSites.append(site)
            }
        }

        if allowDeletes {
            for site in employer.sites where !retainedIDs.contains(site.id) {
                modelContext.delete(site)
            }
        } else {
            for site in employer.sites where !retainedIDs.contains(site.id) {
                updatedSites.append(site)
            }
        }

        employer.sites = updatedSites
    }

    private func syncStreakRules(for employer: Employer, allowDeletes: Bool, insertNewObjects: Bool) {
        var retainedIDs = Set<UUID>()
        var updatedRules: [StreakRule] = []
        let lastRuleIndex = streakRules.indices.last

        for (index, draft) in streakRules.enumerated() {
            if let sourceID = draft.sourceID,
               let existing = employer.streakRules.first(where: { $0.id == sourceID }) {
                existing.requiredDays = draft.requiredDays
                existing.windowType = draft.windowType
                existing.windowDays = draft.windowType == .rollingDays ? draft.windowDays : nil
                existing.bonusAmount = draft.bonusAmount
                existing.isActive = index == lastRuleIndex
                retainedIDs.insert(existing.id)
                updatedRules.append(existing)
            } else {
                let rule = StreakRule(
                    requiredDays: draft.requiredDays,
                    windowType: draft.windowType,
                    windowDays: draft.windowType == .rollingDays ? draft.windowDays : nil,
                    bonusAmount: draft.bonusAmount,
                    isActive: index == lastRuleIndex
                )
                rule.employer = employer
                if insertNewObjects { modelContext.insert(rule) }
                retainedIDs.insert(rule.id)
                updatedRules.append(rule)
            }
        }

        if allowDeletes {
            for rule in employer.streakRules where !retainedIDs.contains(rule.id) {
                modelContext.delete(rule)
            }
        } else {
            for rule in employer.streakRules where !retainedIDs.contains(rule.id) {
                updatedRules.append(rule)
            }
        }

        employer.streakRules = updatedRules
        employer.keepOnlyNewestActiveStreakRule()
    }

    private func syncCustomBonuses(for employer: Employer, allowDeletes: Bool, insertNewObjects: Bool) {
        var retainedIDs = Set<UUID>()
        var updatedBonuses: [CustomBonusType] = []

        for draft in customBonusTypes {
            let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            if let sourceID = draft.sourceID,
               let existing = employer.customBonusTypes.first(where: { $0.id == sourceID }) {
                existing.name = trimmedName
                existing.payUnit = draft.payUnit
                existing.defaultAmount = draft.defaultAmount
                existing.payoutSchedule = draft.payoutSchedule
                retainedIDs.insert(existing.id)
                updatedBonuses.append(existing)
            } else {
                let bonus = CustomBonusType(
                    employer: employer,
                    name: trimmedName,
                    payUnit: draft.payUnit,
                    defaultAmount: draft.defaultAmount,
                    payoutSchedule: draft.payoutSchedule
                )
                if insertNewObjects { modelContext.insert(bonus) }
                retainedIDs.insert(bonus.id)
                updatedBonuses.append(bonus)
            }
        }

        if allowDeletes {
            for bonus in employer.customBonusTypes where !retainedIDs.contains(bonus.id) {
                modelContext.delete(bonus)
            }
        } else {
            for bonus in employer.customBonusTypes where !retainedIDs.contains(bonus.id) {
                updatedBonuses.append(bonus)
            }
        }

        employer.customBonusTypes = updatedBonuses
    }

    private static func nextEmployerVersionName(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Employer Version" }

        if let range = trimmed.range(of: #" v(\d+)$"#, options: .regularExpression),
           let version = Int(trimmed[range].dropFirst(2)) {
            let prefix = String(trimmed[..<range.lowerBound])
            return "\(prefix) v\(version + 1)"
        }

        return "\(trimmed) v2"
    }
}

// MARK: - Progress Bar

struct WizardProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accent)
                    .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 6)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Draft Models

struct DraftContact: Identifiable {
    var id = UUID()
    var sourceID: UUID? = nil
    var name: String = ""
    var role: String = ""

    var trimmedRole: String? {
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    init(name: String = "", role: String = "") {
        self.name = name
        self.role = role
    }

    init(contact: ContactPerson) {
        self.id = contact.id
        self.sourceID = contact.id
        self.name = contact.name
        self.role = contact.role ?? ""
    }
}

struct DraftSite: Identifiable {
    var id = UUID()
    var sourceID: UUID? = nil
    var name: String = ""
    var payUnit: PayUnit = .perDay
    var baseAmount: Decimal = 0

    init() {}

    init(site: Site) {
        self.id = site.id
        self.sourceID = site.id
        self.name = site.name
        self.payUnit = site.payUnit
        self.baseAmount = site.baseAmount
    }
}

struct DraftStreakRule: Identifiable {
    var id = UUID()
    var sourceID: UUID? = nil
    var requiredDays: Int = 4
    var windowType: StreakWindowType = .rollingDays
    var windowDays: Int = 14
    var bonusAmount: Decimal = 0

    init() {}

    init(rule: StreakRule) {
        self.id = rule.id
        self.sourceID = rule.id
        self.requiredDays = rule.requiredDays
        self.windowType = rule.windowType
        self.windowDays = rule.windowDays ?? 14
        self.bonusAmount = rule.bonusAmount
    }
}

struct DraftCustomBonusType: Identifiable {
    var id = UUID()
    var sourceID: UUID? = nil
    var name: String = ""
    var payUnit: PayUnit = .perDay
    var defaultAmount: Decimal = 0
    var payoutSchedule: BonusPayoutSchedule = .serviceDate

    init() {}

    init(bonus: CustomBonusType) {
        self.id = bonus.id
        self.sourceID = bonus.id
        self.name = bonus.name
        self.payUnit = bonus.payUnit
        self.defaultAmount = bonus.defaultAmount
        self.payoutSchedule = bonus.payoutSchedule
    }
}

// MARK: - Step 1: Employer Info

struct EmployerInfoStep: View {
    @Binding var name: String
    @Binding var payCadence: PayCadence
    @Binding var customCadenceDays: Int
    @Binding var defaultOnCallAmount: Decimal
    @Binding var contactPersons: [DraftContact]

    @State private var showAddContact = false
    @State private var newName = ""
    @State private var newRole = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WizardField(label: "Employer Name") {
                TextField("e.g. Valley Anesthesia Partners", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            WizardField(label: "Pay Cadence") {
                Picker("Pay Cadence", selection: $payCadence) {
                    ForEach(PayCadence.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                if payCadence == .custom {
                    HStack {
                        Text("Every")
                        Stepper("\(customCadenceDays) days", value: $customCadenceDays, in: 1...365)
                    }
                    .font(.title3)
                }
            }

            WizardField(label: "Contacts (optional)") {
                VStack(spacing: 8) {
                    ForEach($contactPersons) { $contact in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name).font(.body.bold())
                                if !contact.role.isEmpty {
                                    Text(contact.role).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                contactPersons.removeAll { $0.id == contact.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        showAddContact = true
                    } label: {
                        Label("Add Contact", systemImage: "plus.circle")
                            .font(.body)
                    }
                }
            }

            WizardField(label: "On-Call Default (optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    CurrencyField(value: $defaultOnCallAmount, placeholder: "0.00")
                    Text("If a shift is marked On-Call later, this default amount will prefill and stay editable per shift.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet(contactPersons: $contactPersons)
        }
    }
}

struct CustomBonusesStep: View {
    @Binding var customBonusTypes: [DraftCustomBonusType]
    let isEditingExistingEmployer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Optional: create named bonus buttons that will appear later when you enter a shift for this employer.")
                .font(.body)
                .foregroundStyle(.secondary)

            if customBonusTypes.isEmpty {
                Button {
                    customBonusTypes.append(DraftCustomBonusType())
                } label: {
                    Label("Add Custom Bonus", systemImage: "plus.circle.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Text("No custom bonuses yet")
                        .font(.headline)
                    Text("Examples: Call Back, Weekend, Holiday, Trauma. You can skip this screen if this employer does not use extra named bonuses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            } else {
                HStack {
                    Text("Custom bonus types")
                        .font(.headline)
                    Spacer()
                    Button {
                        customBonusTypes.append(DraftCustomBonusType())
                    } label: {
                        Label("Add Another", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                ForEach($customBonusTypes) { $bonus in
                    CustomBonusTypeEditorCard(
                        bonus: $bonus,
                        canDelete: !(isEditingExistingEmployer && bonus.sourceID != nil)
                    ) {
                        customBonusTypes.removeAll { $0.id == bonus.id }
                    }
                }
            }
        }
    }
}

struct CustomBonusTypeEditorCard: View {
    @Binding var bonus: DraftCustomBonusType
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Bonus name", text: $bonus.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("How this bonus pays", selection: $bonus.payUnit) {
                Text("Per Day / Flat").tag(PayUnit.perDay)
                Text("Per Hour").tag(PayUnit.perHour)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text(bonus.payUnit == .perHour ? "Default Rate Per Hour" : "Default Amount")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CurrencyField(value: $bonus.defaultAmount, placeholder: "0.00")
            }

            Picker("When paid", selection: $bonus.payoutSchedule) {
                ForEach(BonusPayoutSchedule.allCases, id: \.self) { schedule in
                    Text(schedule.rawValue).tag(schedule)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AddContactSheet: View {
    @Binding var contactPersons: [DraftContact]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        WizardField(label: "Name") {
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3)
                        }

                        WizardField(label: "Role (optional)") {
                            TextField("Role", text: $role)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(CatalystFriendlyScrollDismiss())

                Divider()

                HStack(spacing: 12) {
                    Button(role: .cancel) { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    ModalFooterButton(
                        title: "Add Contact",
                        systemImage: "plus.circle",
                        isDisabled: trimmedName.isEmpty
                    ) {
                        contactPersons.append(DraftContact(name: trimmedName, role: role.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                }
                .padding(16)
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCancelButton { dismiss() }
                }
            }
        }
    }
}

// MARK: - Step 2: Sites

struct SitesStep: View {
    @Binding var sites: [DraftSite]
    let isEditingExistingEmployer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add the hospitals or surgical centers where you work.")
                .foregroundStyle(.secondary)

            ForEach($sites) { $site in
                SiteEditorCard(
                    site: $site,
                    canDelete: !(isEditingExistingEmployer && site.sourceID != nil),
                    onDelete: {
                        sites.removeAll { $0.id == site.id }
                    }
                )
            }

            Button {
                sites.append(DraftSite())
            } label: {
                Label("Add Another Site", systemImage: "plus.circle")
                    .font(.body)
            }
        }
    }
}

struct SiteEditorCard: View {
    @Binding var site: DraftSite
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Site name", text: $site.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pay Unit").font(.caption).foregroundStyle(.secondary)
                    Picker("Pay Unit", selection: $site.payUnit) {
                        Text("Per Day").tag(PayUnit.perDay)
                        Text("Per Hour").tag(PayUnit.perHour)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(site.payUnit == .perDay ? "Base / day" : "Base / hour")
                        .font(.caption).foregroundStyle(.secondary)
                    CurrencyField(value: $site.baseAmount, placeholder: "0.00")
                }
            }

        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step 3: Streak Rules

struct StreakRulesStep: View {
    @Binding var rules: [DraftStreakRule]
    let isEditingExistingEmployer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Streak bonuses kick in when you hit a qualifying number of shifts. Only one streak rule can be active per employer.")
                .foregroundStyle(.secondary)

            if rules.isEmpty {
                Button {
                    rules.append(DraftStreakRule())
                } label: {
                    Label("Add Streak Rule", systemImage: "plus.circle")
                        .font(.body)
                }

                Text("No streak rules — you can add them later in Settings.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                Text("Streak bonus rule")
                    .font(.headline)

                Text("If this employer needs a materially different streak setup later, prefer creating a new employer version rather than mutating historical behavior.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach($rules) { $rule in
                    StreakRuleEditorCard(
                        rule: $rule,
                        canDelete: !(isEditingExistingEmployer && rule.sourceID != nil),
                        onDelete: {
                            rules.removeAll { $0.id == rule.id }
                        }
                    )
                }
            }
        }
    }
}

struct StreakRuleEditorCard: View {
    @Binding var rule: DraftStreakRule
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Streak Rule")
                    .font(.headline)
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Text("Work")
                Stepper("\(rule.requiredDays) days", value: $rule.requiredDays, in: 2...30)
                if rule.windowType == .rollingDays {
                    Text("within")
                    Stepper("\(rule.windowDays) days", value: $rule.windowDays, in: 1...90)
                }
            }
            .font(.body)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Window").font(.caption).foregroundStyle(.secondary)
                    Picker("Window", selection: $rule.windowType) {
                        ForEach(StreakWindowType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bonus Amount").font(.caption).foregroundStyle(.secondary)
                    CurrencyField(value: $rule.bonusAmount, placeholder: "0.00")
                }
            }

        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step 4: Review

struct WizardReviewStep: View {
    let mode: EmployerWizardMode
    let employerName: String
    let payCadence: PayCadence
    let defaultOnCallAmount: Decimal
    let sites: [DraftSite]
    let streakRules: [DraftStreakRule]
    let customBonusTypes: [DraftCustomBonusType]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if mode != .create {
                Text(mode == .edit
                     ? "Existing shifts keep their saved pay snapshots. This review only changes employer defaults, site settings, and future rule choices."
                     : "This versioned copy starts future shifts on a new employer record while leaving the original employer history untouched.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            ReviewRow(label: "Employer", value: employerName)
            ReviewRow(label: "Pay Cadence", value: payCadence.rawValue)
            if defaultOnCallAmount > 0 {
                ReviewRow(label: "On-Call Default", value: defaultOnCallAmount.formatted(.currency(code: "USD")))
            }

            Divider()

            Text("Sites").font(.headline)
            ForEach(sites.filter { !$0.name.isEmpty }) { site in
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.name).font(.body.bold())
                    Text("\(site.payUnit.rawValue) · \(site.baseAmount.formatted(.currency(code: "USD")))/\(site.payUnit == .perDay ? "day" : "hr")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            if !customBonusTypes.isEmpty {
                Divider()
                Text("Custom Bonuses").font(.headline)
                ForEach(customBonusTypes.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { bonus in
                    Text("\(bonus.name): \(bonus.defaultAmount.formatted(.currency(code: "USD"))) \(bonus.payUnit == .perHour ? "per hour" : "flat/per day") · paid: \(bonus.payoutSchedule.shortLabel)")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if !streakRules.isEmpty {
                Divider()
                Text("Streak Rules").font(.headline)
                ForEach(streakRules) { rule in
                    Text("Work \(rule.requiredDays) days in \(rule.windowType == .rollingDays ? "\(rule.windowDays) rolling days" : rule.windowType.rawValue) → \(rule.bonusAmount.formatted(.currency(code: "USD")))")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}


struct CatalystFriendlyScrollDismiss: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
        #else
        content.scrollDismissesKeyboard(.interactively)
        #endif
    }
}

// MARK: - Wizard Field Wrapper

struct WizardField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content
        }
    }
}
