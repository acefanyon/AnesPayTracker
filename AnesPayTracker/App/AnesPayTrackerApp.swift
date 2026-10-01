import SwiftUI
import SwiftData

@main
struct AnesPayTrackerApp: App {

    /// nil only when the saved data could not be opened. In that case the app
    /// shows an error screen instead of starting with an empty store, so a
    /// failed upgrade can never look like (or become) lost data.
    let modelContainer: ModelContainer?
    let startupError: String?

    init() {
        StoreSafety.backUpStoreIfNeeded()
        do {
            let container = try Self.makeContainer()
            modelContainer = container
            startupError = nil

            #if DEBUG
            // Development/demo seed data only.
            SeedData.insertIfNeeded(into: container.mainContext)
            #endif
        } catch {
            modelContainer = nil
            startupError = String(describing: error)
        }
    }

    private static func makeContainer() throws -> ModelContainer {
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
        return try ModelContainer(for: schema, configurations: [config])
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .modelContainer(modelContainer)
            } else {
                StoreOpenFailedView(details: startupError ?? "Unknown error")
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // Custom new-item command handled in-app
            }
        }

        #if os(macOS)
        Settings {
            if let modelContainer {
                SettingsView()
                    .modelContainer(modelContainer)
            }
        }
        #endif
    }
}

// MARK: - Store Safety

/// Protects the on-device store, which is the only copy of the user's pay
/// records (there is no iCloud sync).
enum StoreSafety {
    private static let storeFileNames = ["default.store", "default.store-wal", "default.store-shm"]
    private static let backupFolderPrefix = "before-build-"
    private static let backupsToKeep = 3

    static var backupsDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("StoreBackups", isDirectory: true)
    }

    /// Copies the store files aside once per app build, before the store is
    /// opened (and possibly migrated) by that build. Must run before any
    /// ModelContainer opens the store, so the copy is a consistent snapshot.
    static func backUpStoreIfNeeded() {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        guard fm.fileExists(atPath: support.appendingPathComponent("default.store").path) else { return }

        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let destination = backupsDirectory.appendingPathComponent(backupFolderPrefix + build, isDirectory: true)
        guard !fm.fileExists(atPath: destination.path) else { return }

        // Copy into a staging folder first so a half-finished copy is never
        // mistaken for a complete backup.
        let staging = backupsDirectory.appendingPathComponent(".in-progress-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for name in storeFileNames {
                let source = support.appendingPathComponent(name)
                if fm.fileExists(atPath: source.path) {
                    try fm.copyItem(at: source, to: staging.appendingPathComponent(name))
                }
            }
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            return
        }
        pruneOldBackups()
    }

    private static func pruneOldBackups() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for leftover in entries where leftover.lastPathComponent.hasPrefix(".in-progress-") {
            try? fm.removeItem(at: leftover)
        }

        let backups = entries
            .filter { $0.lastPathComponent.hasPrefix(backupFolderPrefix) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
        for old in backups.dropFirst(backupsToKeep) {
            try? fm.removeItem(at: old)
        }
    }
}

// MARK: - Store Open Failed View

struct StoreOpenFailedView: View {
    let details: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("AnesPay couldn't open your saved data")
                    .font(.title2.bold())

                Text("Nothing has been deleted. Your shifts and pay records are still on this device.")
                    .font(.body)

                Text("Please don't delete the app — that would remove the data. Install the next update, or contact the developer and share the details below.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text(details)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
    }
}
