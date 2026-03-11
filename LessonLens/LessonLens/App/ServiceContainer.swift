import SwiftUI
import Observation

/// Dependency injection container for all services
@MainActor
@Observable
final class ServiceContainer {
    static let shared = ServiceContainer()

    // MARK: - Services
    let authService: AuthService
    let recordingService: RecordingService
    let audioImportService: AudioImportService
    let videoImportService: VideoImportService
    let transcriptionService: TranscriptionService
    let analysisService: AnalysisService
    let videoAnalysisService: VideoAnalysisService
    let audioExtractionService: AudioExtractionService
    let techniqueService: TechniqueService
    let exportService: ExportService
    let chatService: ChatService

    // MARK: - Configuration
    let config: AppConfiguration

    private init() {
        self.config = AppConfiguration.load()

        // Initialize services
        self.authService = AuthService(config: config)
        self.recordingService = RecordingService(config: config)
        self.audioImportService = AudioImportService(config: config)
        self.videoImportService = VideoImportService(config: config)
        self.transcriptionService = TranscriptionService(config: config)
        self.analysisService = AnalysisService(config: config)
        self.videoAnalysisService = VideoAnalysisService(config: config)
        self.audioExtractionService = AudioExtractionService()
        self.techniqueService = TechniqueService()
        self.exportService = ExportService()
        self.chatService = ChatService(config: config)
    }
}

// MARK: - App Configuration

struct AppConfiguration: Codable {
    let backendURL: URL
    let googleClientID: String
    let allowedDomain: String
    let minRecordingDuration: TimeInterval
    let maxRecordingDuration: TimeInterval
    let whisperModel: String
    let rateLimitPerHour: Int
    let devBypassAuth: Bool
    let devUseBundledModel: Bool

    static func load() -> AppConfiguration {
        // Default configuration - can be overridden by config file
        AppConfiguration(
            backendURL: URL(string: "https://lessonlens-api-885969573209.us-west1.run.app")!,
            googleClientID: "885969573209-spelnfqo14pamiqtdc6st6c35auoe5ub.apps.googleusercontent.com",
            allowedDomain: "psd401.net",
            minRecordingDuration: 5 * 60,  // 5 minutes
            maxRecordingDuration: 50 * 60, // 50 minutes
            whisperModel: "openai_whisper-large-v3",
            rateLimitPerHour: 20,
            devBypassAuth: ProcessInfo.processInfo.environment["DEV_BYPASS_AUTH"] == "1",
            devUseBundledModel: ProcessInfo.processInfo.environment["DEV_USE_BUNDLED_MODEL"] == "1"
        )
    }
}

// MARK: - Environment Key

extension EnvironmentValues {
    @Entry var serviceContainer: ServiceContainer = .shared
}

extension View {
    func environment(_ container: ServiceContainer) -> some View {
        environment(\.serviceContainer, container)
    }
}
