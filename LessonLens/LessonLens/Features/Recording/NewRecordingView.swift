import SwiftUI
import SwiftData

struct NewRecordingView: View {
    @Binding var isPresented: Bool
    let onComplete: (Recording) -> Void

    @Environment(\.serviceContainer) private var services
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var title = ""
    @State private var currentRecording: Recording?
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var errorMessage: String?
    @State private var showingConfirmCancel = false
    @State private var hasPermission = false

    private let minDuration: TimeInterval = 5 * 60  // 5 minutes
    private let maxDuration: TimeInterval = 90 * 60 // 90 minutes

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    if isRecording {
                        showingConfirmCancel = true
                    } else {
                        isPresented = false
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("New Recording")
                    .font(PSDFonts.headline)

                Spacer()

                Button("Done") {
                    finishRecording()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canFinish)
            }
            .padding()

            Spacer()

            // Recording interface
            if !hasPermission {
                PermissionRequestView {
                    requestPermission()
                }
            } else if isRecording {
                RecordingInProgressView(
                    title: title.isEmpty ? "Teaching Session" : title,
                    duration: recordingDuration,
                    audioLevel: audioLevel,
                    minDuration: minDuration,
                    maxDuration: maxDuration
                )
            } else {
                RecordingSetupView(
                    title: $title,
                    onStart: startRecording
                )
            }

            Spacer()

            // Recording controls
            if hasPermission {
                RecordingControlsView(
                    isRecording: isRecording,
                    canStop: recordingDuration >= minDuration,
                    onToggle: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                )
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Duration info
            if hasPermission {
                Text("Recording must be 5-90 minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            checkPermission()
        }
        .onDisappear {
            if isRecording {
                services.recordingService.cancelRecording()
            }
        }
        .alert("Cancel Recording?", isPresented: $showingConfirmCancel) {
            Button("Keep Recording", role: .cancel) { }
            Button("Discard", role: .destructive) {
                services.recordingService.cancelRecording()
                isPresented = false
            }
        } message: {
            Text("Your current recording will be discarded.")
        }
        .onReceive(services.recordingService.$currentDuration) { duration in
            recordingDuration = duration
        }
        .onReceive(services.recordingService.$audioLevel) { level in
            audioLevel = level
        }
    }

    private var canFinish: Bool {
        !isRecording && currentRecording != nil && recordingDuration >= minDuration
    }

    private func checkPermission() {
        hasPermission = services.recordingService.hasPermission()
    }

    private func requestPermission() {
        Task {
            hasPermission = await services.recordingService.requestPermission()
            if !hasPermission {
                errorMessage = "Microphone access is required to record teaching sessions."
            }
        }
    }

    private func startRecording() {
        Task {
            do {
                let sessionTitle = title.isEmpty ? "Teaching Session \(formattedDate)" : title
                let recording = try await services.recordingService.startRecording(title: sessionTitle)

                currentRecording = recording
                isRecording = true
                errorMessage = nil

                // Insert into SwiftData
                modelContext.insert(recording)
                try modelContext.save()

            } catch let error as RecordingError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    private func stopRecording() {
        let duration = services.recordingService.stopRecording()
        recordingDuration = duration
        isRecording = false

        // Update recording
        if let recording = currentRecording {
            recording.duration = duration
            recording.status = .recorded

            do {
                try modelContext.save()
            } catch {
                errorMessage = "Failed to save recording: \(error.localizedDescription)"
            }
        }
    }

    private func finishRecording() {
        guard let recording = currentRecording else { return }
        onComplete(recording)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Microphone Access Required")
                .font(PSDFonts.title2)

            Text("LessonLens needs access to your microphone to record teaching sessions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Grant Access") {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Recording Setup View

struct RecordingSetupView: View {
    @Binding var title: String
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            TextField("Session Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            Text("Press the record button or click Start to begin")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recording In Progress View

struct RecordingInProgressView: View {
    let title: String
    let duration: TimeInterval
    let audioLevel: Float
    let minDuration: TimeInterval
    let maxDuration: TimeInterval

    var body: some View {
        VStack(spacing: 24) {
            // Animated recording indicator
            ZStack {
                Circle()
                    .fill(.red.opacity(0.2))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(.red.opacity(0.3))
                    .frame(width: 100 + CGFloat(audioLevel) * 40, height: 100 + CGFloat(audioLevel) * 40)
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)

                Circle()
                    .fill(.red)
                    .frame(width: 20, height: 20)
            }

            Text(title)
                .font(PSDFonts.title2)

            // Duration display
            Text(formattedDuration)
                .font(.system(size: 48, weight: .light, design: .monospaced))

            // Progress to minimum
            if duration < minDuration {
                VStack(spacing: 4) {
                    ProgressView(value: duration, total: minDuration)
                        .frame(maxWidth: 300)

                    Text("Minimum \(Int(minDuration / 60)) minutes required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Ready to stop")
                    .font(.callout)
                    .foregroundStyle(PSDTheme.success)
            }

            // Warning near max
            if duration >= maxDuration * 0.9 {
                Text("Approaching maximum duration")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Recording Controls View

struct RecordingControlsView: View {
    let isRecording: Bool
    let canStop: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            ZStack {
                Circle()
                    .fill(isRecording ? .red : .accentColor)
                    .frame(width: 72, height: 72)

                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isRecording && !canStop)
        .help(isRecording ? (canStop ? "Stop Recording" : "Minimum 5 minutes required") : "Start Recording")
    }
}

#Preview {
    NewRecordingView(isPresented: .constant(true)) { _ in }
        .environmentObject(AppState())
        .environment(ServiceContainer.shared)
}
