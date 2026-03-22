import SwiftUI
import AVKit

/// NSViewRepresentable wrapper around AVPlayerView.
/// Bypasses _AVKit_SwiftUI's VideoPlayer which has a Swift runtime
/// metadata crash on macOS Tahoe 26.x (getSuperclassMetadata failure).
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

/// Simple video player view for previewing recordings
struct VideoPlayerView: View {
    let videoURL: URL?

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        Group {
            if let player = player {
                NativeVideoPlayer(player: player)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                placeholder
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: videoURL) {
            setupPlayer()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Video not available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func setupPlayer() {
        guard let url = videoURL else {
            player = nil
            return
        }

        player = AVPlayer(url: url)
    }
}

/// Compact video thumbnail view for lists
struct VideoThumbnailView: View {
    let videoURL: URL?
    let duration: TimeInterval

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 45)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 80, height: 45)
                    .cornerRadius(4)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundStyle(.secondary)
                    )
            }

            // Duration badge
            Text(formatDuration(duration))
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .foregroundStyle(.white)
                .cornerRadius(2)
                .padding(4)
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        guard let url = videoURL else { return }

        Task {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)

            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

                await MainActor.run {
                    self.thumbnail = nsImage
                }
            } catch {
                // Silently fail - placeholder will be shown
            }
        }
    }

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
    VStack(spacing: 20) {
        VideoPlayerView(videoURL: nil)
            .frame(width: 400, height: 300)

        VideoThumbnailView(videoURL: nil, duration: 600)
    }
    .padding()
}
