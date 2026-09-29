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
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema mismatch — delete the incompatible store and retry
            print("ModelContainer failed: \(error). Deleting store and retrying...")

            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
                for file in storeFiles {
                    let url = appSupport.appendingPathComponent(file)
                    try? FileManager.default.removeItem(at: url)
                }
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
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
