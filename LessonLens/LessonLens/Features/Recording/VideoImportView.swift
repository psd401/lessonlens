import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// View for importing video files with preview and validation
struct VideoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var showingFileImporter = false
    @State private var selectedURL: URL?
    @State private var videoPlayer: AVPlayer?
    @State private var videoDuration: TimeInterval = 0
    @State private var fileSize: Int64 = 0
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var isImporting = false

    var onImportComplete: ((Recording) -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Import Video")
                .font(.title2)
                .fontWeight(.semibold)

            // Video preview or placeholder
            if let player = videoPlayer {
                NativeVideoPlayer(player: player)
                    .frame(height: 300)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                videoPlaceholder
            }

            // Video info
            if selectedURL != nil {
                videoInfoSection
            }

            // Duration recommendation
            Text("For best results and cost efficiency, we recommend clips of 5-20 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Validation error
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                if selectedURL != nil {
                    Button {
                        importVideo()
                    } label: {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 100)
                        } else {
                            Text("Import Video")
                                .frame(width: 100)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validationError != nil || isImporting)
                } else {
                    Button("Select Video") {
                        showingFileImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 550)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: VideoImportService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer = nil
        }
    }

    // MARK: - Subviews

    private var videoPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Select a video file to import")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Browse Files") {
                showingFileImporter = true
            }
            .buttonStyle(.bordered)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var videoInfoSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label(formatDuration(videoDuration), systemImage: "clock")
                Spacer()
                Label(VideoImportService.formatFileSize(fileSize), systemImage: "doc")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let url = selectedURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            validateAndPreview(url: url)
        case .failure:
            validationError = "Failed to access the selected file"
        }
    }

    private func validateAndPreview(url: URL) {
        isValidating = true
        validationError = nil

        // Start security access
        let didStart = url.startAccessingSecurityScopedResource()

        // Check file exists and is readable
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            validationError = "Cannot read the selected file"
            isValidating = false
            if didStart { url.stopAccessingSecurityScopedResource() }
            return
        }

        // Check format
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v", "webm"].contains(ext) else {
            validationError = "Unsupported video format. Use mp4, mov, m4v, or webm."
            isValidating = false
            if didStart { url.stopAccessingSecurityScopedResource() }
            return
        }

        // Check file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attributes[.size] as? Int64 ?? 0
            if fileSize > VideoImportService.maxFileSize {
                validationError = "Video exceeds 2GB maximum size"
                isValidating = false
                if didStart { url.stopAccessingSecurityScopedResource() }
                return
            }
        } catch {
            validationError = "Cannot determine file size"
            isValidating = false
            if didStart { url.stopAccessingSecurityScopedResource() }
            return
        }

        // Load duration - keep security access until Task completes
        let asset = AVURLAsset(url: url)
        Task {
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)

                await MainActor.run {
                    videoDuration = seconds

                    // Validate duration
                    if seconds < 300 { // 5 minutes
                        validationError = "Video must be at least 5 minutes"
                    } else if seconds > 3000 { // 50 minutes
                        validationError = "Video cannot exceed 50 minutes"
                    } else {
                        validationError = nil
                        selectedURL = url
                        videoPlayer = AVPlayer(url: url)
                    }

                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    validationError = "Cannot determine video duration"
                    isValidating = false
                }
            }
        }
    }

    private func importVideo() {
        guard let url = selectedURL else { return }

        isImporting = true

        Task {
            do {
                let recording = try await services.videoImportService.importVideoFile(from: url)
                modelContext.insert(recording)
                onImportComplete?(recording)
                dismiss()
            } catch let error as VideoImportError {
                appState.handleError(.videoImportError(error))
                isImporting = false
            } catch {
                appState.handleError(.videoImportError(.copyFailed(error)))
                isImporting = false
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

#Preview {
    VideoImportView()
        .environmentObject(AppState())
        .environment(ServiceContainer.shared)
}
