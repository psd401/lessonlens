import Foundation
import SwiftData

// MARK: - Media Type

enum MediaType: String, Codable {
    case audio
    case video
}

/// Represents a teaching session recording
@Model
final class Recording {
    // MARK: - Properties
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFilePath: String  // Relative path within app's Documents
    var videoFilePath: String?  // Relative path for video files
    var mediaType: MediaType = MediaType.audio
    var status: RecordingStatus
    var isImported: Bool = false

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \Transcript.recording)
    var transcript: Transcript?

    @Relationship(deleteRule: .cascade, inverse: \Analysis.recording)
    var analysis: Analysis?

    @Relationship(deleteRule: .cascade, inverse: \Reflection.recording)
    var reflection: Reflection?

    @Relationship(deleteRule: .cascade, inverse: \ChatSession.recording)
    var chatSessions: [ChatSession]?

    // MARK: - Computed Properties
    var absoluteAudioPath: URL? {
        guard let documentsURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }

        return documentsURL
            .appendingPathComponent("com.peninsula.lessonlens")
            .appendingPathComponent("Recordings")
            .appendingPathComponent(audioFilePath)
    }

    var absoluteVideoPath: URL? {
        guard let videoFilePath = videoFilePath,
              let documentsURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
              ).first else { return nil }

        return documentsURL
            .appendingPathComponent("com.peninsula.lessonlens")
            .appendingPathComponent("Recordings")
            .appendingPathComponent(videoFilePath)
    }

    var isVideo: Bool {
        mediaType == .video
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var isComplete: Bool {
        status == .complete
    }

    var canBeAnalyzed: Bool {
        status == .transcribed && transcript != nil
    }

    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFilePath: String,
        videoFilePath: String? = nil,
        mediaType: MediaType = .audio,
        status: RecordingStatus = .recording,
        isImported: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.videoFilePath = videoFilePath
        self.mediaType = mediaType
        self.status = status
        self.isImported = isImported
    }
}

// MARK: - Recording Status

enum RecordingStatus: String, Codable {
    case recording
    case recorded
    case uploading  // Video upload to cloud for analysis
    case transcribing
    case transcribed
    case analyzing
    case complete
    case failed

    var displayText: String {
        switch self {
        case .recording: return "Recording"
        case .recorded: return "Recorded"
        case .uploading: return "Uploading..."
        case .transcribing: return "Transcribing..."
        case .transcribed: return "Ready for Analysis"
        case .analyzing: return "Analyzing..."
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }

    var isProcessing: Bool {
        self == .uploading || self == .transcribing || self == .analyzing
    }
}

// MARK: - Interrupted Processing

extension Recording {
    /// Where a recording should land if the app quit while it was uploading,
    /// transcribing or analyzing: back to the last step that finished, so the
    /// teacher can start the next one again. nil when it isn't mid-process.
    var statusAfterInterruptedProcessing: RecordingStatus? {
        guard status.isProcessing else { return nil }
        if analysis != nil { return .complete }
        if transcript != nil { return .transcribed }
        return .recorded
    }

    /// Resets recordings left mid-process by a quit or crash. Nothing is still
    /// processing at launch, so any such status is stale. Returns the count reset.
    @discardableResult
    static func resetInterruptedProcessing(in context: ModelContext) -> Int {
        guard let recordings = try? context.fetch(FetchDescriptor<Recording>()) else { return 0 }

        var reset = 0
        for recording in recordings {
            if let status = recording.statusAfterInterruptedProcessing {
                recording.status = status
                reset += 1
            }
        }

        if reset > 0 {
            try? context.save()
        }
        return reset
    }
}
