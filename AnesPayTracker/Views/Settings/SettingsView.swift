import SwiftUI
import SwiftData

// MARK: - Settings View

struct SettingsView: View {
    @Query private var employers: [Employer]
    @Environment(\.modelContext) private var modelContext
    
    @State private var showAddEmployer = false
    @State private var showCalendarSettings = false
    @State private var selectedEmployer: Employer?
    
    var body: some View {
        NavigationStack {
            List {
                // Employers
                Section {
                    ForEach(employers) { employer in
                        NavigationLink {
                            EmployerDetailSettings(employer: employer)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(employer.name).font(.body.bold())
                                Text("\(employer.sites.count) site\(employer.sites.count == 1 ? "" : "s") · \(employer.payCadence.rawValue)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Button {
                        showAddEmployer = true
                    } label: {
                        Label("Add Employer", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accent)
                    }
                } header: {
                    Text("Employers")
                }
                
                // Calendar
                Section("Calendar") {
                    NavigationLink("Calendar Sync") {
                        CalendarSettingsView()
                    }
                }
                
                // Display
                Section("Display") {
                    NavigationLink("Text Size") {
                        TextSizeSettings()
                    }
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Data Storage")
                        Spacer()
                        Text("On-device + iCloud").foregroundStyle(.secondary).font(.footnote)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddEmployer) {
                EmployerSetupWizard()
            }
        }
    }
}

// MARK: - Employer Detail Settings

struct EmployerDetailSettings: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var employer: Employer
    
    @State private var showEditEmployer = false
    @State private var showDuplicateEmployerVersion = false
    @State private var showAddSite = false
    @State private var showAddStreak = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                Button {
                    showEditEmployer = true
                } label: {
                    Label("Open Full Employer Editor", systemImage: "square.and.pencil")
                }

                Button {
                    showDuplicateEmployerVersion = true
                } label: {
                    Label("Create Versioned Copy", systemImage: "plus.square.on.square")
                }
            } header: {
                Text("Employer-Wide Changes")
            } footer: {
                Text("Use the full editor for global default changes. Saved shifts keep their existing pay snapshots. If the new setup should only apply going forward, create a versioned copy instead of rewriting the original employer.")
            }

            // Basic info
            Section("Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $employer.name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                Picker("Pay Cadence", selection: $employer.payCadence) {
                    ForEach(PayCadence.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }

                if employer.payCadence == .custom {
                    HStack {
                        Text("Every")
                        Spacer()
                        Stepper(
                            "\(employer.customCadenceDays ?? 14) days",
                            value: Binding(
                                get: { employer.customCadenceDays ?? 14 },
                                set: { employer.customCadenceDays = $0 }
                            ),
                            in: 1...365
                        )
                    }
                }

                HStack {
                    Text("Default On-Call Bonus")
                    Spacer()
                    CurrencyField(value: Binding(
                        get: { employer.defaultOnCallAmount },
                        set: { employer.defaultOnCallAmount = $0 }
                    ), placeholder: "0.00")
                    .frame(width: 120)
                }
            }
            
            // Contacts
            Section("Contacts") {
                ForEach(employer.contactPersons) { contact in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.body.bold())
                            if let role = contact.role {
                                Text(role).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet { modelContext.delete(employer.contactPersons[i]) }
                }
                
                Button {
                    // inline add via sheet
                } label: {
                    Label("Add Contact", systemImage: "plus.circle")
                        .foregroundStyle(Color.accent)
                }
            }
            
            // Sites
            Section("Sites") {
                ForEach(employer.sites) { site in
                    NavigationLink {
                        SiteDetailSettings(site: site)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name).font(.body.bold())
                            Text("\(site.payUnit.rawValue) · \(site.baseAmount.formatted(.currency(code: "USD")))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Button {
                    showAddSite = true
                } label: {
                    Label("Add Site", systemImage: "plus.circle")
                        .foregroundStyle(Color.accent)
                }
            }
            
            // Streak rules
            Section("Streak Rules") {
                if employer.activeStreakRules.count > 1 {
                    Text("Multiple active streak rules were found. The newest active rule will be used until you clean this up.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    Text("Only one streak rule should be active per employer. Keep older rules inactive for reference or future employer-versioning.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(employer.streakRules) { rule in
                    NavigationLink {
                        StreakRuleSettings(rule: rule)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.description).font(.footnote)
                            Text(rule.isActive ? "Active rule" : "Inactive archive")
                                .font(.caption)
                                .foregroundStyle(rule.isActive ? .green : .secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Button {
                    showAddStreak = true
                } label: {
                    Label("Add Streak Rule", systemImage: "plus.circle")
                        .foregroundStyle(Color.accent)
                }
            }
            
            // Delete
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Employer", systemImage: "trash")
                }
            }
        }
        .navigationTitle(employer.name)
        .confirmationDialog("Delete \(employer.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Employer & All Data", role: .destructive) {
                modelContext.delete(employer)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("This will permanently delete all sites and shifts under this employer.")
        }
        .sheet(isPresented: $showAddSite) {
            AddSiteSheet(employer: employer)
        }
        .sheet(isPresented: $showAddStreak) {
            AddStreakRuleSheet(employer: employer)
        }
        .sheet(isPresented: $showEditEmployer) {
            EmployerSetupWizard(mode: .edit, sourceEmployer: employer)
        }
        .sheet(isPresented: $showDuplicateEmployerVersion) {
            EmployerSetupWizard(mode: .duplicateVersion, sourceEmployer: employer)
        }
    }
}

// MARK: - Site Detail Settings

struct SiteDetailSettings: View {
    @Bindable var site: Site
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            Section("Site Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Site name", text: $site.name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                
                Picker("Pay Unit", selection: $site.payUnit) {
                    ForEach(PayUnit.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                
                HStack {
                    Text("Base Rate")
                    Spacer()
                    CurrencyField(value: Binding(
                        get: { site.baseAmount },
                        set: { site.baseAmount = $0 }
                    ), placeholder: "0.00")
                    .frame(width: 120)
                }
            }
            
            Section {
                HStack {
                    Text("Total shifts")
                    Spacer()
                    Text(site.shifts.count.description).foregroundStyle(.secondary)
                }
            } header: {
                Text("Stats")
            }
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Streak Rule Settings

struct StreakRuleSettings: View {
    @Bindable var rule: StreakRule
    @Environment(\.modelContext) private var modelContext

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { rule.isActive },
            set: { newValue in
                if newValue {
                    rule.employer?.activateOnlyStreakRule(rule)
                } else {
                    rule.isActive = false
                }
                try? modelContext.save()
            }
        )
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Required Days")
                    Spacer()
                    Stepper("\(rule.requiredDays)", value: $rule.requiredDays, in: 2...30)
                }
                
                Picker("Window", selection: $rule.windowType) {
                    ForEach(StreakWindowType.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                
                if rule.windowType == .rollingDays {
                    HStack {
                        Text("Window Days")
                        Spacer()
                        Stepper("\(rule.windowDays ?? 14)", value: Binding(
                            get: { rule.windowDays ?? 14 },
                            set: { rule.windowDays = $0 }
                        ), in: 1...90)
                    }
                }
                
                HStack {
                    Text("Bonus Amount")
                    Spacer()
                    CurrencyField(value: $rule.bonusAmount, placeholder: "0.00")
                        .frame(width: 120)
                }
                
                Toggle("Active", isOn: activeBinding)
            } header: {
                Text("Rule")
            } footer: {
                Text("Only one streak rule can be active per employer. Turning this on automatically turns the others off.")
            }
        }
        .navigationTitle("Streak Rule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Site Sheet

struct AddSiteSheet: View {
    let employer: Employer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var draft = DraftSite()
    
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    SiteEditorCard(site: $draft, canDelete: true, onDelete: { dismiss() })
                        .padding(24)
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
                        title: "Save Site",
                        systemImage: "checkmark",
                        isDisabled: trimmedName.isEmpty
                    ) {
                        let site = Site(
                            name: trimmedName,
                            payUnit: draft.payUnit,
                            baseAmount: draft.baseAmount
                        )
                        site.employer = employer
                        modelContext.insert(site)
                        try? modelContext.save()
                        dismiss()
                    }
                }
                .padding(16)
            }
            .navigationTitle("Add Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCancelButton { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add Streak Rule Sheet

struct AddStreakRuleSheet: View {
    let employer: Employer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var draft = DraftStreakRule()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    StreakRuleEditorCard(rule: $draft, canDelete: true, onDelete: { dismiss() })
                        .padding(24)
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
                    
                    ModalFooterButton(title: "Save Streak Rule", systemImage: "checkmark") {
                        let rule = StreakRule(
                            requiredDays: draft.requiredDays,
                            windowType: draft.windowType,
                            windowDays: draft.windowType == .rollingDays ? draft.windowDays : nil,
                            bonusAmount: draft.bonusAmount
                        )
                        rule.employer = employer
                        employer.activateOnlyStreakRule(rule)
                        modelContext.insert(rule)
                        try? modelContext.save()
                        dismiss()
                    }
                }
                .padding(16)
            }
            .navigationTitle("Add Streak Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCancelButton { dismiss() }
                }
            }
        }
    }
}

// MARK: - Calendar Settings View

struct CalendarSettingsView: View {
    @State private var calSync = CalendarSyncManager.shared
    @State private var showCreateCalendar = false
    
    var body: some View {
        List {
            Section {
                Toggle("Sync shifts to Calendar", isOn: Binding(
                    get: { calSync.isOptedIn },
                    set: { val in
                        calSync.isOptedIn = val
                        if val && !calSync.isAuthorized {
                            Task { await calSync.requestAccess() }
                        }
                    }
                ))
            } footer: {
                Text("New shifts will be added to your selected calendar as all-day events.")
            }
            
            if calSync.isOptedIn {
                Section("Selected Calendar") {
                    ForEach(calSync.availableCalendars, id: \.calendarIdentifier) { cal in
                        Button {
                            calSync.setSelectedCalendar(cal)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: cal.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(cal.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if cal.calendarIdentifier == calSync.selectedCalendarID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accent)
                                }
                            }
                        }
                    }
                    
                    Button("Create 'Work' Calendar") {
                        _ = calSync.createWorkCalendar()
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
        .navigationTitle("Calendar Sync")
    }
}

// MARK: - Text Size Settings

struct TextSizeSettings: View {
    var body: some View {
        List {
            Section {
                Text("AnesPay uses your system's Dynamic Type size by default, respecting your accessibility preferences.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            Section("System Setting") {
                Link("Open Accessibility Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    .foregroundStyle(Color.accent)
            }
            
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("$2,850.00")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.accent)
                    Text("Riverside Surgical · Full Day")
                        .font(.title3)
                    Text("Base $1,800 + High Need Bonus $350 + Streak $500")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Logged 3 days ago")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Text Size")
    }
}
