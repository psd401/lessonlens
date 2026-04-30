import SwiftUI

/// Top-level page explaining how LessonLens works and addressing privacy concerns
struct HowItWorksView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(PSDTheme.accent)

                Text("How It Works")
                    .font(PSDFonts.largeTitle)
                    .foregroundStyle(PSDTheme.headingText(for: colorScheme))

                Text("Private AI coaching for your professional growth.")
                    .font(PSDFonts.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }

            // Steps
            VStack(alignment: .leading, spacing: 20) {
                StepRow(
                    number: 1,
                    icon: "mic.fill",
                    title: "Record or Import",
                    description: "Capture a lesson using your device's microphone, or import an existing audio or video file."
                )

                StepRow(
                    number: 2,
                    icon: "book.pages",
                    title: "Choose a Framework",
                    description: "Select the teaching framework you'd like coaching feedback aligned to — PSD Essentials, Danielson, TLAC, and more."
                )

                StepRow(
                    number: 3,
                    icon: "sparkles",
                    title: "Receive Feedback",
                    description: "AI analyzes your transcript and provides actionable coaching feedback tied to specific techniques and look-fors."
                )
            }
            .frame(maxWidth: 500)

            // Privacy section
            VStack(spacing: 12) {
                Label("Your Privacy", systemImage: "lock.fill")
                    .font(PSDFonts.headline)
                    .foregroundStyle(PSDTheme.accent)

                VStack(alignment: .leading, spacing: 8) {
                    PrivacyPoint(text: "Your recordings, transcripts, and feedback are yours alone.")
                    PrivacyPoint(text: "No administrator, evaluator, or colleague can see your sessions.")
                    PrivacyPoint(text: "Audio recordings are transcribed on your device and never uploaded. Video uploads are sent to Google for analysis and automatically deleted immediately afterward.")
                    PrivacyPoint(text: "Transcripts and analysis data are processed in the cloud but never permanently stored — Google retains nothing after processing.")
                    PrivacyPoint(text: "Your data is never used to train AI models.")
                }
                .frame(maxWidth: 500)

                Text("Use of LessonLens is completely voluntary and self-directed. It is not an evaluation tool and will never be used for personnel decisions. This is a personal growth tool — use it to reflect, experiment, and improve at your own pace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Text("Teach Like a Champion / TLAC, AVID and WICOR, the Danielson Framework, and NBPTS are trademarks of their respective owners. LessonLens is not affiliated with, endorsed by, or sponsored by these organizations.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .psdPageBackground()
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(PSDTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(PSDTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)")
                    .font(PSDFonts.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy Point

private struct PrivacyPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(PSDTheme.accent)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    HowItWorksView()
}
