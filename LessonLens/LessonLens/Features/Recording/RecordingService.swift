import Foundation
import AVFoundation
import Combine

/// Service for recording audio from the microphone
@MainActor
final class RecordingService: NSObject, ObservableObject {
    private let config: AppConfiguration
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?

    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var error: RecordingError?

    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    // Recording directory
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
        super.init()
    }

    // MARK: - Public Methods

    /// Requests microphone permission
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Checks if microphone permission is granted
    func hasPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Starts a new recording
    func startRecording(title: String) async throws -> Recording {
        guard hasPermission() else {
            throw RecordingError.microphoneAccessDenied
        }

        // Generate unique filename
        let filename = "\(UUID().uuidString).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(filename)

        // Configure audio session for macOS
        #if os(macOS)
        // macOS doesn't use AVAudioSession the same way
        #endif

        // Audio recording settings - using standard sample rate for AAC compatibility
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,  // Standard rate - WhisperKit handles resampling
            AVNumberOfChannelsKey: 1,   // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000  // Higher bitrate for 44.1kHz
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.prepareToRecord() == true else {
                throw RecordingError.audioSessionFailed(NSError(
                    domain: "RecordingService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder"]
                ))
            }

            guard audioRecorder?.record() == true else {
                throw RecordingError.audioSessionFailed(NSError(
                    domain: "RecordingService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"]
                ))
            }

            isRecording = true
            recordingStartTime = Date()
            currentDuration = 0

            // Start duration timer
            startDurationTimer()

            // Start level metering
            startLevelMetering()

            // Create Recording model
            let recording = Recording(
                title: title,
                audioFilePath: filename,
                status: .recording
            )

            return recording

        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.audioSessionFailed(error)
        }
    }

    /// Stops the current recording
    func stopRecording() -> TimeInterval {
        stopTimers()

        let duration = currentDuration
        audioRecorder?.stop()
        audioRecorder = nil

        isRecording = false
        audioLevel = 0

        return duration
    }

    /// Cancels and deletes the current recording
    func cancelRecording() {
        stopTimers()

        if let url = audioRecorder?.url {
            audioRecorder?.stop()
            audioRecorder = nil
            try? FileManager.default.removeItem(at: url)
        }

        isRecording = false
        currentDuration = 0
        audioLevel = 0
    }

    /// Validates recording duration
    func validateDuration(_ duration: TimeInterval) -> RecordingError? {
        if duration < config.minRecordingDuration {
            return .durationTooShort
        }
        if duration > config.maxRecordingDuration {
            return .durationTooLong
        }
        return nil
    }

    /// Gets the file size of a recording
    func getFileSize(for recording: Recording) -> Int64? {
        guard let url = recording.absoluteAudioPath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    // MARK: - Private Methods

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)

                // Auto-stop if max duration reached
                if self.currentDuration >= self.config.maxRecordingDuration {
                    _ = self.stopRecording()
                }
            }
        }
    }

    private func startLevelMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevel()
            }
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
            return
        }

        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)

        // Convert dB to linear scale (0-1)
        // dB range is typically -160 to 0
        let minDb: Float = -60
        let normalizedLevel = max(0, (level - minDb) / abs(minDb))
        audioLevel = normalizedLevel
    }

    private func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension RecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                error = .encodingFailed
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let err = error {
                self.error = .audioSessionFailed(err)
            }
        }
    }
}
