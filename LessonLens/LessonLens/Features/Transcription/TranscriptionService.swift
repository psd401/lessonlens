import Foundation
import WhisperKit

/// Service for transcribing audio using WhisperKit
@MainActor
final class TranscriptionService: ObservableObject {
    private let config: AppConfiguration
    private var whisperKit: WhisperKit?
    private var transcriptionTask: Task<Transcript, Error>?

    @Published var isLoading = false
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var error: TranscriptionError?

    private var isModelLoaded = false
    private var loadedModelName: String = ""
    private var progressTimer: Timer?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Loads the WhisperKit model (should be called on app launch or before first transcription)
    func loadModel() async throws {
        guard !isModelLoaded else { return }

        isLoading = true
        error = nil

        do {
            // Diagnostic logging for model loading
            let bundledPath = findBundledModelPath()
            print("[TranscriptionService] devUseBundledModel: \(config.devUseBundledModel)")
            print("[TranscriptionService] bundledModelPath: \(bundledPath ?? "nil")")
            print("[TranscriptionService] Using mode: \(config.devUseBundledModel && bundledPath != nil ? "bundled" : "production")")

            let whisperConfig: WhisperKitConfig

            if config.devUseBundledModel,
               let bundledModelPath = findBundledModelPath() {
                // Use bundled model for development
                loadedModelName = "openai_whisper-base"
                whisperConfig = WhisperKitConfig(
                    model: loadedModelName,
                    modelFolder: bundledModelPath,
                    computeOptions: .init(
                        melCompute: .cpuAndGPU,
                        audioEncoderCompute: .cpuAndGPU,
                        textDecoderCompute: .cpuAndGPU
                    ),
                    download: true  // Allow downloading tokenizer files (CoreML models are bundled)
                )
            } else {
                // Production: download model on demand
                loadedModelName = config.whisperModel
                whisperConfig = WhisperKitConfig(
                    model: loadedModelName,
                    computeOptions: .init(
                        melCompute: .cpuAndGPU,
                        audioEncoderCompute: .cpuAndGPU,
                        textDecoderCompute: .cpuAndGPU
                    )
                )
            }

            whisperKit = try await WhisperKit(whisperConfig)
            isModelLoaded = true
            isLoading = false
        } catch {
            isLoading = false
            let transcriptionError = TranscriptionError.modelLoadFailed(error)
            self.error = transcriptionError
            throw transcriptionError
        }
    }

    /// Transcribes audio from a recording
    func transcribe(recording: Recording) async throws -> Transcript {
        // Ensure model is loaded
        if !isModelLoaded {
            try await loadModel()
        }

        guard let whisper = whisperKit else {
            throw TranscriptionError.modelLoadFailed(NSError(
                domain: "TranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit not initialized"]
            ))
        }

        guard let audioURL = recording.absoluteAudioPath else {
            throw TranscriptionError.processingFailed(NSError(
                domain: "TranscriptionService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found"]
            ))
        }

        isTranscribing = true
        progress = 0
        error = nil
        startProgressPolling()

        let startTime = Date()

        do {
            // Create a task for cancellation support
            transcriptionTask = Task {
                try await performTranscription(whisper: whisper, audioURL: audioURL)
            }

            let transcript = try await transcriptionTask!.value

            stopProgressPolling()
            isTranscribing = false
            progress = 1.0

            // Update processing time
            let processingTime = Date().timeIntervalSince(startTime)
            return Transcript(
                id: transcript.id,
                fullText: transcript.fullText,
                createdAt: transcript.createdAt,
                modelUsed: loadedModelName,
                processingTime: processingTime,
                segments: transcript.segments
            )

        } catch is CancellationError {
            stopProgressPolling()
            isTranscribing = false
            throw TranscriptionError.cancelled
        } catch {
            stopProgressPolling()
            isTranscribing = false
            let transcriptionError = TranscriptionError.processingFailed(error)
            self.error = transcriptionError
            throw transcriptionError
        }
    }

    /// Cancels the current transcription
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        stopProgressPolling()
        isTranscribing = false
        progress = 0
    }

    // MARK: - Progress Polling

    private func startProgressPolling() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isTranscribing else { return }
                self.progress = min(self.whisperKit?.progress.fractionCompleted ?? 0, 0.99)
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Private Methods

    private func performTranscription(whisper: WhisperKit, audioURL: URL) async throws -> Transcript {
        // Transcribe with progress tracking
        let result = try await whisper.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: "en",
                temperature: 0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 3,
                topK: 5,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: true,
                clipTimestamps: [],
                chunkingStrategy: .vad  // Voice Activity Detection for natural breaks
            )
        ) { _ in
            return true  // Continue transcription
        }

        // Check for cancellation
        try Task.checkCancellation()

        // Convert WhisperKit result to our Transcript model
        let segments = result.flatMap { transcriptionResult -> [TranscriptSegment] in
            transcriptionResult.segments.map { segment in
                TranscriptSegment(
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    text: segment.text,
                    confidence: Float(exp(segment.avgLogprob))  // Convert log prob to probability
                )
            }
        }

        // Detect pauses (gaps >= 3.0 seconds between segments)
        let pauses = detectPauses(in: segments, threshold: 3.0)

        let fullText = result.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return Transcript(
            fullText: fullText,
            createdAt: Date(),
            modelUsed: loadedModelName,
            processingTime: 0,  // Will be updated by caller
            segments: segments,
            pauses: pauses
        )
    }

    /// Detects pauses (silence) between transcript segments
    private func detectPauses(in segments: [TranscriptSegment], threshold: TimeInterval) -> [TranscriptPause] {
        guard segments.count > 1 else { return [] }

        var pauses: [TranscriptPause] = []
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }

        for i in 0..<(sortedSegments.count - 1) {
            let current = sortedSegments[i]
            let next = sortedSegments[i + 1]
            let gap = next.startTime - current.endTime

            if gap >= threshold {
                pauses.append(TranscriptPause(
                    startTime: current.endTime,
                    endTime: next.startTime,
                    precedingText: extractLastWords(from: current.text, count: 5),
                    followingText: extractFirstWords(from: next.text, count: 5)
                ))
            }
        }
        return pauses
    }

    /// Extracts the last N words from a string
    private func extractLastWords(from text: String, count: Int) -> String {
        let words = text.split(separator: " ")
        let lastWords = words.suffix(count)
        return lastWords.joined(separator: " ")
    }

    /// Extracts the first N words from a string
    private func extractFirstWords(from text: String, count: Int) -> String {
        let words = text.split(separator: " ")
        let firstWords = words.prefix(count)
        return firstWords.joined(separator: " ")
    }

    /// Checks if sufficient memory is available for transcription
    func checkMemoryAvailability() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return true }  // Default to allowing if check fails

        // WhisperKit large-v3 needs ~2-3GB RAM
        let usedMemory = info.resident_size
        let availableMemory = ProcessInfo.processInfo.physicalMemory - usedMemory

        // Require at least 3GB available
        return availableMemory > 3 * 1024 * 1024 * 1024
    }

    /// Finds the bundled model path
    /// Returns the folder containing the mlmodelc files directly
    private func findBundledModelPath() -> String? {
        // Try: Models/openai_whisper-base - return full path to model folder
        if let modelPath = Bundle.main.path(forResource: "openai_whisper-base", ofType: nil, inDirectory: "Models") {
            print("[TranscriptionService] Found bundled model at: \(modelPath)")
            // Verify expected files exist
            let fm = FileManager.default
            let melPath = (modelPath as NSString).appendingPathComponent("MelSpectrogram.mlmodelc")
            print("[TranscriptionService] MelSpectrogram exists: \(fm.fileExists(atPath: melPath)) at \(melPath)")
            return modelPath
        }

        // Try: openai_whisper-base at root of Resources
        if let modelPath = Bundle.main.path(forResource: "openai_whisper-base", ofType: nil) {
            print("[TranscriptionService] Found model at root: \(modelPath)")
            return modelPath
        }

        print("[TranscriptionService] No bundled model found. Bundle path: \(Bundle.main.bundlePath)")

        // Fallback: Model files directly in Resources - copy to temp folder with correct structure
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let requiredFiles = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        let allFilesExist = requiredFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: (resourcePath as NSString).appendingPathComponent(file))
        }

        guard allFilesExist else { return nil }

        // Create model folder in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelFolder = appSupport.appendingPathComponent("WhisperModels/openai_whisper-base")

        // If already set up, return it
        if FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("config.json").path) {
            return modelFolder.path
        }

        // Create and populate model folder
        do {
            try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

            let filesToCopy = requiredFiles + ["generation_config.json"]
            for file in filesToCopy {
                let source = (resourcePath as NSString).appendingPathComponent(file)
                let dest = modelFolder.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: source) {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(atPath: source, toPath: dest.path)
                }
            }
            return modelFolder.path
        } catch {
            print("Failed to set up model folder: \(error)")
            return nil
        }
    }
}
