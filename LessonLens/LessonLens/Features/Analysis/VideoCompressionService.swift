import Foundation
import AVFoundation

/// Makes a 720p MP4 copy of a video for upload.
///
/// Gemini samples about one frame per second at a fixed token cost per frame,
/// so resolution above 720p adds upload time without improving analysis. The
/// copy goes to a temporary folder; the original recording is never changed.
@MainActor
final class VideoCompressionService {
    private var exportSession: AVAssetExportSession?

    private var uploadsDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LessonLensUploads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Exports a 720p MP4 copy of the video. The caller deletes the returned file
    /// when it's done with it (see `removeCompressedCopy`).
    func compressForUpload(_ videoURL: URL, onProgress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw VideoCompressionError.exportSessionFailed
        }
        self.exportSession = exportSession
        defer { self.exportSession = nil }

        let outputURL = uploadsDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        exportSession.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled {
                onProgress(Double(exportSession.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { progressTask.cancel() }

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if exportSession.status == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw VideoCompressionError.exportFailed
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VideoCompressionError.exportFailed
        }
        onProgress(1.0)
        return outputURL
    }

    /// Cancels an export in progress
    func cancel() {
        exportSession?.cancelExport()
    }

    /// Deletes a copy made by `compressForUpload`
    func removeCompressedCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum VideoCompressionError: Error, LocalizedError {
    case exportSessionFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .exportSessionFailed, .exportFailed:
            return "Couldn't prepare the video for upload"
        }
    }
}
