import SwiftUI
import SwiftData
import CoreData

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
        do {
            let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)
            PersistentStore.launchIssue = issue
            return container
        } catch {
            fatalError("Could not open or set aside the LessonLens store: \(error)")
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

    static func legacyStoreURL(in appSupport: URL) -> URL {
        appSupport.appendingPathComponent(legacyStoreName)
    }

    /// Opens the store, moving or setting it aside as needed. Returns the
    /// container plus an issue to show the teacher, if any. Throws only when
    /// no store can be opened at all.
    static func openContainer(
        schema: Schema,
        appSupport: URL,
        fileManager: FileManager = .default
    ) throws -> (container: ModelContainer, issue: StorageError?) {
        let storeURL = storeURL(in: appSupport)
        let legacyURL = legacyStoreURL(in: appSupport)

        var openURL = storeURL
        var movedLegacyStore = false
        do {
            movedLegacyStore = try moveLegacyStoreIfNeeded(appSupport: appSupport, fileManager: fileManager)
        } catch {
            // Keep working from default.store this launch. Opening the new
            // location would create an empty store there, and the move would
            // never be retried.
            print("Could not move legacy store: \(error). Opening it in place.")
            openURL = legacyURL
        }

        func open(_ url: URL) throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: true)])
        }

        do {
            return (try open(openURL), nil)
        } catch {
            // Never delete teacher data: it exists only on this Mac. Put the
            // store aside, start an empty one, and tell the teacher.
            print("ModelContainer failed: \(error). Setting store aside and retrying...")

            let issue: StorageError
            if openURL == legacyURL {
                // Opened in place and failed: leave default.store untouched.
                issue = .legacyStoreUnreadable
            } else if movedLegacyStore, (try? restoreLegacyStore(appSupport: appSupport, fileManager: fileManager)) != nil {
                issue = .legacyStoreUnreadable
            } else {
                let backupURL = try setAside(storeURL: storeURL, fileManager: fileManager)
                issue = .storeSetAside(backupName: backupURL.lastPathComponent)
            }
            return (try open(storeURL), issue)
        }
    }

    /// True if the store at `url` was created by LessonLens. Reads the store's
    /// metadata (which lists its entity names) without opening it. Throws if
    /// the file can't be read as a store.
    static func isLessonLensStore(at url: URL) throws -> Bool {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil
        )
        let entities = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
        return entities["Recording"] != nil && entities["Transcript"] != nil
    }

    /// Moves default.store from the Application Support root into the app's
    /// folder when the app has no store there yet and default.store is a
    /// LessonLens store. Another app's default.store is left alone. Returns
    /// true if it moved.
    static func moveLegacyStoreIfNeeded(appSupport: URL, fileManager: FileManager = .default) throws -> Bool {
        let storeURL = storeURL(in: appSupport)
        let legacyURL = legacyStoreURL(in: appSupport)
        guard !fileManager.fileExists(atPath: storeURL.path),
              fileManager.fileExists(atPath: legacyURL.path),
              try isLessonLensStore(at: legacyURL) else { return false }

        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try moveFiles(from: legacyURL, to: storeURL, fileManager: fileManager)
        return true
    }

    /// Undoes moveLegacyStoreIfNeeded, for a default.store that would not open.
    static func restoreLegacyStore(appSupport: URL, fileManager: FileManager = .default) throws {
        try moveFiles(
            from: storeURL(in: appSupport),
            to: legacyStoreURL(in: appSupport),
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
