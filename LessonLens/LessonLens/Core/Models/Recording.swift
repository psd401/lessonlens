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

// MARK: - Media File Cleanup

extension Recording {
    /// The Recordings folder that audioFilePath and videoFilePath are relative to
    static var recordingsDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.peninsula.lessonlens")
            .appendingPathComponent("Recordings")
    }

    /// Deletes the recording and saves, then removes its audio and video files
    /// (a video session has the original video and the extracted audio),
    /// except any a re-analysis copy still uses. Nothing is removed if the
    /// save fails.
    static func deleteWithMedia(_ recording: Recording, in context: ModelContext, directory: URL? = Recording.recordingsDirectory) {
        let mediaFiles = [recording.audioFilePath, recording.videoFilePath]
        context.delete(recording)
        guard (try? context.save()) != nil else { return }
        removeUnreferencedMedia(mediaFiles, in: context, directory: directory)
    }

    /// Points the recording at newly extracted audio, saves, and removes the
    /// audio it replaces, unless that's the video itself or a re-analysis
    /// copy uses it
    func replaceAudioFile(with fileName: String, in context: ModelContext, directory: URL? = Recording.recordingsDirectory) {
        let previous = audioFilePath
        audioFilePath = fileName
        guard (try? context.save()) != nil else { return }
        Recording.removeUnreferencedMedia([previous], in: context, directory: directory)
    }

    /// Deletes each named media file that no recording still uses as its audio
    /// or video file. Call after the recording that used it was deleted or
    /// pointed at a new file, and saved. Re-analysis copies share their
    /// original's files, so a shared file stays until its last user is gone.
    /// If the recordings can't be fetched, nothing is deleted. Returns the
    /// names of the files removed.
    @discardableResult
    static func removeUnreferencedMedia(
        _ fileNames: [String?],
        in context: ModelContext,
        directory: URL? = Recording.recordingsDirectory
    ) -> [String] {
        guard let directory, let inUse = mediaFilesInUse(in: context) else { return [] }

        var removed: [String] = []
        for name in Set(fileNames.compactMap { $0 }) {
            // Names are bare file names; anything else could reach outside the folder
            guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", !inUse.contains(name) else { continue }
            let url = directory.appendingPathComponent(name)
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed.append(name)
            }
        }
        return removed
    }

    /// Every file name a recording uses as its audio or video, or nil if the
    /// recordings can't be fetched
    static func mediaFilesInUse(in context: ModelContext) -> Set<String>? {
        guard let recordings = try? context.fetch(FetchDescriptor<Recording>()) else { return nil }
        var inUse = Set<String>()
        for recording in recordings {
            inUse.insert(recording.audioFilePath)
            if let video = recording.videoFilePath { inUse.insert(video) }
        }
        return inUse
    }

    /// Files in the Recordings folder that no recording uses, with their sizes
    /// in bytes: left behind by deletes and re-extractions before COR-01 was
    /// fixed. Skips files changed in the last 10 minutes, which a recording,
    /// import or audio extraction may still be writing. nil if the folder or
    /// the recordings can't be read.
    static func unusedMediaFiles(
        in context: ModelContext,
        directory: URL? = Recording.recordingsDirectory,
        now: Date = Date()
    ) -> [(name: String, bytes: Int64)]? {
        guard let directory,
              let inUse = mediaFilesInUse(in: context),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return nil }

        var unused: [(name: String, bytes: Int64)] = []
        for url in urls where !inUse.contains(url.lastPathComponent) {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > 10 * 60 else { continue }
            unused.append((url.lastPathComponent, Int64(values.fileSize ?? 0)))
        }
        return unused.sorted { $0.name < $1.name }
    }
}
