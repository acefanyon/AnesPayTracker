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
                CustomBonusType.self,
                ContactPerson.self,
            ])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            modelContainer = container

            #if DEBUG
            // Development/demo seed data only.
            SeedData.insertIfNeeded(into: container.mainContext)
            #else
            // One-time safety cleanup for TestFlight/release users who already
            // received legacy demo data. This removes only known sample records
            // and leaves user-created employers/data intact.
            SeedData.removeLegacyDemoDataIfNeeded(into: container.mainContext)
            #endif
        } catch {
            // If migration fails (e.g. new non-optional attribute added), delete
            // the old store and start fresh. Acceptable for a development build.
            let storeURL = URL.applicationSupportDirectory
                .appendingPathComponent("default.store")
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("store-wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("store-shm"))
            do {
                let schema = Schema([
                    Employer.self,
                    Site.self,
                    Shift.self,
                    StreakRule.self,
                    CustomBonusType.self,
                    ContactPerson.self,
                ])
                let config = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .automatic
                )
                let container = try ModelContainer(for: schema, configurations: [config])
                modelContainer = container
                #if DEBUG
                // Development/demo seed data only.
                SeedData.insertIfNeeded(into: container.mainContext)
                #endif
            } catch {
                fatalError("Failed to create ModelContainer after store reset: \(error)")
            }
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
