import SwiftUI
import SwiftData

@main
struct AnesPayTrackerApp: App {
    
    let modelContainer: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                Employer.self,
                Site.self,
                Shift.self,
                StreakRule.self,
                ContactPerson.self,
            ])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            
            // Seed on first launch
            Task { @MainActor in
                SeedData.insertIfNeeded(into: modelContainer.mainContext)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // Custom new-item command handled in-app
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        #endif
    }
}
