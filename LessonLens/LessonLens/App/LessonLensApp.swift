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
        Recording.finalizeInterruptedRecordings(in: sharedModelContainer.mainContext)
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

    /// Set at launch when the teacher needs to know about the store; shown
    /// once per launch.
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

        func open(_ url: URL) throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: true)])
        }

        // Move default.store in if it's ours and there's nothing here yet. If
        // the move fails, work from default.store this launch rather than
        // create an empty store here, so the move is retried next launch.
        if !fileManager.fileExists(atPath: storeURL.path), isLessonLensStoreFile(at: legacyURL) {
            do {
                try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try moveFiles(from: legacyURL, to: storeURL, fileManager: fileManager)
            } catch {
                print("Could not move legacy store: \(error). Opening it in place.")
                if let container = try? open(legacyURL) {
                    return (container, nil)
                }
            }
        }

        var issue: StorageError?
        let container: ModelContainer
        do {
            container = try open(storeURL)
        } catch {
            // Never delete teacher data: it exists only on this Mac. Set the
            // store aside, start an empty one, and tell the teacher.
            print("ModelContainer failed: \(error). Setting store aside and retrying...")
            // If even the rename fails, this throws and the app stops rather
            // than run on a temporary store that would lose new sessions.
            let backupURL = try setAside(storeURL: storeURL, fileManager: fileManager)
            issue = .storeSetAside(backupName: backupURL.lastPathComponent)
            container = try open(storeURL)
        }

        // A LessonLens default.store that is still there wasn't brought in
        // (it couldn't be moved or opened). Say so on every launch until it's
        // resolved, so those sessions never disappear silently.
        if issue == nil, isLessonLensStoreFile(at: legacyURL) {
            issue = .legacyStoreUnreadable
        }
        // A default.store whose metadata can't be read may be another app's,
        // so it's only flagged (every launch) when the Recordings folder shows
        // LessonLens was used on this Mac.
        if issue == nil,
           fileManager.fileExists(atPath: legacyURL.path),
           (try? isLessonLensStore(at: legacyURL)) == nil,
           let recordings = try? fileManager.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().appendingPathComponent("Recordings").path),
           !recordings.isEmpty {
            issue = .legacyStoreUnverified
        }
        return (container, issue)
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

    /// False when the file is missing, unreadable, or another app's store:
    /// default.store is only ever touched when it's known to be LessonLens's.
    static func isLessonLensStoreFile(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && (try? isLessonLensStore(at: url)) == true
    }

    /// True when a store other than the open one may still list sessions whose
    /// files are in Recordings/: a set-aside backup, or a default.store that
    /// is LessonLens's or can't be read. Those sessions' files look unused to
    /// the open store, so the unused-file cleanup must not run. Also true if
    /// the folder can't be listed.
    static func hasOtherStore(appSupport: URL, fileManager: FileManager = .default) -> Bool {
        let folder = appSupport.appendingPathComponent(folderName)
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return true }
        if names.contains(where: { $0.hasPrefix("LessonLens-backup-") && $0.hasSuffix(".store") }) {
            return true
        }
        let legacyURL = legacyStoreURL(in: appSupport)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return false }
        return (try? isLessonLensStore(at: legacyURL)) != false
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
