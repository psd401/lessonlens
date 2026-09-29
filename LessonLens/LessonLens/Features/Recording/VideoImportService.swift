import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Service for importing video files from external sources
@MainActor
final class VideoImportService: ObservableObject {
    private let config: AppConfiguration

    /// Supported video file types for import
    static let supportedTypes: [UTType] = [
        .mpeg4Movie,      // .mp4
        .quickTimeMovie,  // .mov
        UTType(filenameExtension: "m4v") ?? .movie,  // .m4v
        UTType(mimeType: "video/webm") ?? .movie     // .webm
    ]

    /// Maximum imported file size in bytes. Videos are compressed to 720p before
    /// upload, so this only bounds local storage; the upload itself must be under 2GB.
    static let maxFileSize: Int64 = 10 * 1024 * 1024 * 1024

    // Recording directory (same as RecordingService)
    private lazy var recordingsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("com.peninsula.lessonlens")
            .appendingPathComponent("Recordings")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init(config: AppConfiguration) {
        self.config = config
    }

    /// Imports a video file from an external URL
    /// - Parameter sourceURL: The URL of the video file to import (security-scoped)
    /// - Returns: A Recording model with status .recorded and mediaType .video
    /// - Throws: VideoImportError if validation or import fails
    func importVideoFile(from sourceURL: URL) async throws -> Recording {
        // Start accessing security-scoped resource
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Validate file is readable
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw VideoImportError.fileNotReadable
        }

        // Validate video format
        guard isValidVideoFormat(sourceURL) else {
            throw VideoImportError.invalidVideoFormat
        }

        // Validate file size
        let fileSize = try getFileSize(at: sourceURL)
        if fileSize > Self.maxFileSize {
            throw VideoImportError.fileTooLarge
        }

        // Get duration
        let duration = try await getVideoDuration(from: sourceURL)

        // Validate duration
        if let validationError = validateDuration(duration) {
            throw validationError
        }

        // Generate unique filename preserving original extension
        let originalExtension = sourceURL.pathExtension.lowercased()
        let filename = "\(UUID().uuidString).\(originalExtension)"
        let destinationURL = recordingsDirectory.appendingPathComponent(filename)

        // Copy file to recordings directory
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw VideoImportError.copyFailed(error)
        }

        // Generate title from original filename
        let originalFilename = sourceURL.deletingPathExtension().lastPathComponent
        let title = originalFilename.isEmpty ? "Imported Video" : originalFilename

        // Create Recording model with video type
        let recording = Recording(
            title: title,
            createdAt: Date(),
            duration: duration,
            audioFilePath: filename,  // Use same field for compatibility
            videoFilePath: filename,
            mediaType: .video,
            status: .recorded,
            isImported: true
        )

        return recording
    }

    /// Checks if the file has a valid video format
    private func isValidVideoFormat(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let validExtensions = ["mp4", "mov", "m4v", "webm"]
        return validExtensions.contains(ext)
    }

    /// Gets the file size in bytes
    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int64 else {
            throw VideoImportError.fileNotReadable
        }
        return size
    }

    /// Gets the duration of a video file
    private func getVideoDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)

            // Check if duration is valid
            guard seconds.isFinite && seconds > 0 else {
                throw VideoImportError.durationUnavailable
            }

            return seconds
        } catch _ as VideoImportError {
            throw VideoImportError.durationUnavailable
        } catch {
            throw VideoImportError.durationUnavailable
        }
    }

    /// Validates the duration against configured limits
    private func validateDuration(_ duration: TimeInterval) -> VideoImportError? {
        if duration < config.minRecordingDuration {
            return .durationTooShort
        }
        if duration > config.maxRecordingDuration {
            return .durationTooLong
        }
        return nil
    }

    /// Formats file size for display
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Video Import Errors

enum VideoImportError: Error, LocalizedError {
    case fileNotReadable
    case invalidVideoFormat
    case fileTooLarge
    case durationTooShort
    case durationTooLong
    case durationUnavailable
    case copyFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable:
            return "Cannot read the selected file"
        case .invalidVideoFormat:
            return "Invalid video format. Supported formats: mp4, mov, m4v, webm"
        case .fileTooLarge:
            return "Video file exceeds 10GB maximum size"
        case .durationTooShort:
            return "Video must be at least 5 minutes"
        case .durationTooLong:
            return "Video cannot exceed 90 minutes"
        case .durationUnavailable:
            return "Unable to determine video duration"
        case .copyFailed(let error):
            return "Failed to import file: \(error.localizedDescription)"
        }
    }
}
