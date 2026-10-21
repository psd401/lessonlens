import SwiftUI
import SwiftData

@main
struct LessonLensApp: App {
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Transcript.self,
            Analysis.self,
            TechniqueEvaluation.self,
            Technique.self,
            UserSettings.self,
            Reflection.self,
            ChatSession.self,
            ChatMessage.self
        ])
        // Unit tests launch the app as their host, and an unsigned test build
        // isn't sandboxed, so keep tests away from the teacher's real store.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [inMemory])
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = PersistentStore.storeURL(in: appSupport)

        var movedLegacyStore = false
        do {
            movedLegacyStore = try PersistentStore.moveLegacyStoreIfNeeded(appSupport: appSupport)
        } catch {
            print("Could not move legacy store: \(error)")
        }

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Never delete teacher data: it exists only on this Mac. Put the
            // store aside, start an empty one, and tell the teacher where it went.
            print("ModelContainer failed: \(error). Setting store aside and retrying...")

            if movedLegacyStore, (try? PersistentStore.restoreLegacyStore(appSupport: appSupport)) != nil {
                // The generic default.store may belong to another app; leave it where it was.
                PersistentStore.launchIssue = .legacyStoreUnreadable
            } else {
                do {
                    let backupURL = try PersistentStore.setAside(storeURL: storeURL)
                    PersistentStore.launchIssue = .storeSetAside(backupName: backupURL.lastPathComponent)
                } catch {
                    fatalError("Could not open or set aside the LessonLens store: \(error)")
                }
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after setting the store aside: \(error)")
            }
        }
    }()

    init() {
        TranscriptionService.backfillMissingPauses(in: sharedModelContainer.mainContext)
        Recording.resetInterruptedProcessing(in: sharedModelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(ServiceContainer.shared)
                .tint(PSDTheme.accent)
                .onOpenURL { _ in }
                .onAppear {
                    PSDFonts.registerFonts()
                    if let issue = PersistentStore.launchIssue {
                        PersistentStore.launchIssue = nil
                        appState.handleError(.storage(issue))
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environment(ServiceContainer.shared)
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}

// MARK: - Persistent Store Location

/// Where the SwiftData store lives, and how it is moved or set aside.
/// The store holds every teacher's sessions and exists only on this Mac,
/// so these helpers move and rename files but never delete them.
enum PersistentStore {
    static let folderName = "com.peninsula.lessonlens"
    static let storeName = "LessonLens.store"
    /// SwiftData's default name, used through v1.2.0. In an unsandboxed
    /// Release build it sits in the shared Application Support root.
    static let legacyStoreName = "default.store"

    /// SQLite keeps the store in up to three files that must move together.
    static let fileSuffixes = ["", "-shm", "-wal"]

    /// Set when launch had to set the store aside; shown once to the teacher.
    static var launchIssue: StorageError?

    static func storeURL(in appSupport: URL) -> URL {
        appSupport.appendingPathComponent(folderName).appendingPathComponent(storeName)
    }

    /// Moves default.store from the Application Support root into the app's
    /// folder when the app has no store there yet. Returns true if it moved.
    static func moveLegacyStoreIfNeeded(appSupport: URL, fileManager: FileManager = .default) throws -> Bool {
        let storeURL = storeURL(in: appSupport)
        let legacyURL = appSupport.appendingPathComponent(legacyStoreName)
        guard !fileManager.fileExists(atPath: storeURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else { return false }

        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try moveFiles(from: legacyURL, to: storeURL, fileManager: fileManager)
        return true
    }

    /// Undoes moveLegacyStoreIfNeeded, for a default.store that would not open.
    static func restoreLegacyStore(appSupport: URL, fileManager: FileManager = .default) throws {
        try moveFiles(
            from: storeURL(in: appSupport),
            to: appSupport.appendingPathComponent(legacyStoreName),
            fileManager: fileManager
        )
    }

    /// Renames the store files to a timestamped backup in the same folder and
    /// returns the backup's URL. The backup can be opened as a store later.
    static func setAside(storeURL: URL, date: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("LessonLens-backup-\(formatter.string(from: date)).store")
        try moveFiles(from: storeURL, to: backupURL, fileManager: fileManager)
        return backupURL
    }

    /// Moves each existing store file; if one move fails, moves the earlier ones back.
    private static func moveFiles(from source: URL, to destination: URL, fileManager: FileManager) throws {
        var moved: [(from: URL, to: URL)] = []
        do {
            for suffix in fileSuffixes {
                let from = URL(fileURLWithPath: source.path + suffix)
                guard fileManager.fileExists(atPath: from.path) else { continue }
                let to = URL(fileURLWithPath: destination.path + suffix)
                try fileManager.moveItem(at: from, to: to)
                moved.append((from, to))
            }
        } catch {
            for pair in moved.reversed() {
                try? fileManager.moveItem(at: pair.to, to: pair.from)
            }
            throw error
        }
    }
}
