import SwiftUI
import SwiftData

// MARK: - Employer Setup Wizard

struct EmployerSetupWizard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var step: WizardStep = .employerInfo
    @State private var employerName = ""
    @State private var payCadence: PayCadence = .biweekly
    @State private var customCadenceDays = 14
    @State private var contactPersons: [DraftContact] = []
    @State private var sites: [DraftSite] = [DraftSite()]
    @State private var streakRules: [DraftStreakRule] = []
    
    @State private var newContactName = ""
    @State private var newContactRole = ""
    
    enum WizardStep: Int, CaseIterable {
        case employerInfo = 0
        case sites = 1
        case streakRules = 2
        case review = 3
        
        var title: String {
            switch self {
            case .employerInfo: return "Employer Info"
            case .sites: return "Sites & Rates"
            case .streakRules: return "Streak Rules"
            case .review: return "Review"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress
                WizardProgressBar(currentStep: step.rawValue, totalSteps: WizardStep.allCases.count)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Step title
                Text(step.title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 24) {
                        switch step {
                        case .employerInfo:
                            EmployerInfoStep(
                                name: $employerName,
                                payCadence: $payCadence,
                                customCadenceDays: $customCadenceDays,
                                contactPersons: $contactPersons
                            )
                        case .sites:
                            SitesStep(sites: $sites)
                        case .streakRules:
                            StreakRulesStep(rules: $streakRules)
                        case .review:
                            WizardReviewStep(
                                employerName: employerName,
                                payCadence: payCadence,
                                sites: sites,
                                streakRules: streakRules
                            )
                        }
                    }
                    .padding(24)
                }
                
                Divider()
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if step.rawValue > 0 {
                        Button("Back") {
                            withAnimation { step = WizardStep(rawValue: step.rawValue - 1) ?? .employerInfo }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    
                    Spacer()
                    
                    Button(step == .review ? "Save Employer" : "Next") {
                        if step == .review {
                            saveEmployer()
                        } else {
                            withAnimation { step = WizardStep(rawValue: step.rawValue + 1) ?? .review }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(step == .employerInfo && employerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(24)
            }
            .navigationTitle("Add Employer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step.rawValue > 0 {
                        ModalBackButton {
                            withAnimation { step = WizardStep(rawValue: step.rawValue - 1) ?? .employerInfo }
                        }
                    } else {
                        ModalCancelButton { dismiss() }
                    }
                }
            }
        }
    }
    
    private func saveEmployer() {
        let employer = Employer(
            name: employerName.trimmingCharacters(in: .whitespaces),
            payCadence: payCadence,
            customCadenceDays: payCadence == .custom ? customCadenceDays : nil
        )
        
        employer.contactPersons = contactPersons.map {
            ContactPerson(name: $0.name, role: $0.role.isEmpty ? nil : $0.role)
        }
        
        let siteObjects = sites.compactMap { draft -> Site? in
            guard !draft.name.isEmpty else { return nil }
            let site = Site(
                name: draft.name,
                payUnit: draft.payUnit,
                baseAmount: draft.baseAmount,
                defaultSplashAmount: draft.hasDefaultSplash ? draft.defaultSplashAmount : nil
            )
            site.employer = employer
            return site
        }
        employer.sites = siteObjects
        
        let ruleObjects = streakRules.map { draft -> StreakRule in
            let rule = StreakRule(
                requiredDays: draft.requiredDays,
                windowType: draft.windowType,
                windowDays: draft.windowType == .rollingDays ? draft.windowDays : nil,
                bonusAmount: draft.bonusAmount
            )
            rule.employer = employer
            return rule
        }
        employer.streakRules = ruleObjects
        
        modelContext.insert(employer)
        for site in siteObjects { modelContext.insert(site) }
        for rule in ruleObjects { modelContext.insert(rule) }
        try? modelContext.save()
        dismiss()
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
    var name: String = ""
    var role: String = ""
}

struct DraftSite: Identifiable {
    var id = UUID()
    var name: String = ""
    var payUnit: PayUnit = .perDay
    var baseAmount: Decimal = 0
    var hasDefaultSplash: Bool = false
    var defaultSplashAmount: Decimal = 0
}

struct DraftStreakRule: Identifiable {
    var id = UUID()
    var requiredDays: Int = 4
    var windowType: StreakWindowType = .rollingDays
    var windowDays: Int = 14
    var bonusAmount: Decimal = 0
}

// MARK: - Step 1: Employer Info

struct EmployerInfoStep: View {
    @Binding var name: String
    @Binding var payCadence: PayCadence
    @Binding var customCadenceDays: Int
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
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet(contactPersons: $contactPersons)
        }
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
                .scrollDismissesKeyboard(.interactively)
                
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add the hospitals or surgical centers where you work.")
                .foregroundStyle(.secondary)
            
            ForEach($sites) { $site in
                SiteEditorCard(site: $site, onDelete: {
                    sites.removeAll { $0.id == site.id }
                })
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
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Site").font(.headline)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            
            TextField("Site name", text: $site.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Pay Unit").font(.subheadline).foregroundStyle(.secondary)
                Picker("Pay Unit", selection: $site.payUnit) {
                    Text("Per Day").tag(PayUnit.perDay)
                    Text("Per Hour").tag(PayUnit.perHour)
                }
                .pickerStyle(.segmented)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(site.payUnit == .perDay ? "Base Rate (per day)" : "Base Rate (per hour)")
                    .font(.subheadline).foregroundStyle(.secondary)
                CurrencyField(value: $site.baseAmount, placeholder: "0.00")
            }
            
            Toggle("Default splash amount?", isOn: $site.hasDefaultSplash)
            
            if site.hasDefaultSplash {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default Splash Amount").font(.subheadline).foregroundStyle(.secondary)
                    CurrencyField(value: $site.defaultSplashAmount, placeholder: "0.00")
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step 3: Streak Rules

struct StreakRulesStep: View {
    @Binding var rules: [DraftStreakRule]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Streak bonuses kick in when you hit a qualifying number of shifts. You can add multiple rules.")
                .foregroundStyle(.secondary)
            
            ForEach($rules) { $rule in
                StreakRuleEditorCard(rule: $rule, onDelete: {
                    rules.removeAll { $0.id == rule.id }
                })
            }
            
            Button {
                rules.append(DraftStreakRule())
            } label: {
                Label("Add Streak Rule", systemImage: "plus.circle")
                    .font(.body)
            }
            
            if rules.isEmpty {
                Text("No streak rules — you can add them later in Settings.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }
}

struct StreakRuleEditorCard: View {
    @Binding var rule: DraftStreakRule
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Streak Rule").font(.headline)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }
            
            HStack {
                Text("Work")
                Stepper("\(rule.requiredDays) days", value: $rule.requiredDays, in: 2...30)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Window").font(.subheadline).foregroundStyle(.secondary)
                Picker("Window", selection: $rule.windowType) {
                    ForEach(StreakWindowType.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                
                if rule.windowType == .rollingDays {
                    HStack {
                        Text("within")
                        Stepper("\(rule.windowDays) days", value: $rule.windowDays, in: 1...90)
                            .font(.title3)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Bonus Amount").font(.subheadline).foregroundStyle(.secondary)
                CurrencyField(value: $rule.bonusAmount, placeholder: "0.00")
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step 4: Review

struct WizardReviewStep: View {
    let employerName: String
    let payCadence: PayCadence
    let sites: [DraftSite]
    let streakRules: [DraftStreakRule]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ReviewRow(label: "Employer", value: employerName)
            ReviewRow(label: "Pay Cadence", value: payCadence.rawValue)
            
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
