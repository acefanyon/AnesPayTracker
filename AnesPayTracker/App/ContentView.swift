import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var employers: [Employer]
    
    @State private var showSetupWizard = false
    @State private var showAddShift = false
    @State private var selectedTab: AppTab = .calendar
    
    var body: some View {
        Group {
            if employers.isEmpty {
                WelcomeView(showSetupWizard: $showSetupWizard)
            } else {
                mainContent
            }
        }
        .sheet(isPresented: $showSetupWizard) {
            EmployerSetupWizard()
        }
        .sheet(isPresented: $showAddShift) {
            AddShiftView()
        }
        .onAppear {
            if employers.isEmpty {
                showSetupWizard = true
            }
        }
    }
    
    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(AppTab.calendar)
            
            PayPeriodView()
                .tabItem {
                    Label("Pay Periods", systemImage: "dollarsign.circle")
                }
                .tag(AppTab.payPeriods)
            
            StreakStatusView()
                .tabItem {
                    Label("Streaks", systemImage: "flame")
                }
                .tag(AppTab.streaks)
            
            ReportView()
                .tabItem {
                    Label("Report", systemImage: "doc.text")
                }
                .tag(AppTab.report)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .overlay(alignment: .bottomTrailing) {
            AddShiftButton {
                showAddShift = true
            }
            .padding(.bottom, 72)
            .padding(.trailing, 20)
        }
        .tint(Color.accent)
    }
}

enum AppTab: Hashable {
    case calendar, payPeriods, streaks, report, settings
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Binding var showSetupWizard: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "cross.case.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accent)
            
            VStack(spacing: 12) {
                Text("AnesPay")
                    .font(.largeTitle.bold())
                Text("Track your shifts and pay across\nall your employers and sites.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showSetupWizard = true
            } label: {
                Text("Get Started")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Add Shift Floating Button

struct AddShiftButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.accent, in: Circle())
                .shadow(color: Color.accent.opacity(0.4), radius: 8, y: 4)
        }
        .accessibilityLabel("Add Shift")
    }
}

// MARK: - Shared Modal Controls

struct ModalCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Close", systemImage: "xmark")
        }
        .accessibilityLabel("Close")
    }
}

struct ModalCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(role: .cancel, action: action) {
            Label("Cancel", systemImage: "xmark")
        }
        .accessibilityLabel("Cancel")
    }
}

struct ModalBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
        }
        .accessibilityLabel("Back")
    }
}

struct ModalSaveButton: View {
    let title: String
    var systemImage: String = "checkmark"
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .font(.body.bold())
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct ModalFooterButton: View {
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isDisabled)
    }
}
