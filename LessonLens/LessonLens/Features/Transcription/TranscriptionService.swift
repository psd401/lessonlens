import Foundation
import SwiftData
import WhisperKit

/// Service for transcribing audio using WhisperKit
@MainActor
final class TranscriptionService: ObservableObject {
    private let config: AppConfiguration
    /// The model (large-v3 is several GB) stays loaded only while
    /// transcriptions run, plus 5 idle minutes so back-to-back work (a
    /// re-analysis, chat preparing a transcript after a video) doesn't reload
    private lazy var model = IdleUnloader<WhisperKit>(idleDelay: .seconds(5 * 60)) { [unowned self] in
        try await self.loadModel()
    }
    private var transcriptionTask: Task<Transcript, Error>?

    @Published var isLoading = false
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var error: TranscriptionError?

    private var loadedModelName: String = ""
    private var progressTimer: Timer?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Loads the WhisperKit model. Called through `model`, which shares one
    /// load among concurrent transcriptions and unloads it when idle.
    private func loadModel() async throws -> WhisperKit {
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

            let whisper = try await WhisperKit(whisperConfig)
            isLoading = false
            return whisper
        } catch {
            isLoading = false
            let transcriptionError = TranscriptionError.modelLoadFailed(error)
            self.error = transcriptionError
            throw transcriptionError
        }
    }

    /// Transcribes audio from a recording
    func transcribe(recording: Recording) async throws -> Transcript {
        guard let audioURL = recording.absoluteAudioPath else {
            throw TranscriptionError.processingFailed(NSError(
                domain: "TranscriptionService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found"]
            ))
        }

        // Loads the model if needed; end() starts the idle countdown however this exits
        let whisper = try await model.begin()
        defer { model.end() }

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
                segments: transcript.segments,
                pauses: transcript.pauses
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
                self.progress = min(self.model.current?.progress.fractionCompleted ?? 0, 0.99)
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

        // Detect pauses (gaps >= pauseThreshold seconds between segments)
        let pauses = Self.detectPauses(in: segments, threshold: Self.pauseThreshold)

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

    /// Minimum gap between segments, in seconds, that counts as a pause
    nonisolated static let pauseThreshold: TimeInterval = 3.0

    /// Detects pauses (silence) between transcript segments.
    /// Static so stored segments can be reprocessed without loading WhisperKit.
    nonisolated static func detectPauses(in segments: [TranscriptSegment], threshold: TimeInterval) -> [TranscriptPause] {
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

    /// Recomputes pauses for saved transcripts that have segments but no pauses.
    /// Transcripts saved before pauses were persisted have empty pausesData; their
    /// segments are intact, so pauses can be rebuilt without re-running Whisper.
    /// Safe to run on every launch: transcripts that already have pauses are skipped,
    /// and one with no qualifying gaps just stays empty.
    /// - Returns: The number of transcripts that gained pauses.
    @discardableResult
    static func backfillMissingPauses(in context: ModelContext) -> Int {
        guard let transcripts = try? context.fetch(FetchDescriptor<Transcript>()) else { return 0 }

        var updated = 0
        for transcript in transcripts where transcript.pauses.isEmpty {
            let segments = transcript.segments
            guard segments.count > 1 else { continue }

            let pauses = detectPauses(in: segments, threshold: pauseThreshold)
            guard !pauses.isEmpty else { continue }

            transcript.pauses = pauses
            updated += 1
        }

        if updated > 0 {
            try? context.save()  // best-effort; the backfill runs again next launch
            print("Backfilled pauses for \(updated) transcript(s)")
        }
        return updated
    }

    /// Extracts the last N words from a string
    private nonisolated static func extractLastWords(from text: String, count: Int) -> String {
        let words = text.split(separator: " ")
        let lastWords = words.suffix(count)
        return lastWords.joined(separator: " ")
    }

    /// Extracts the first N words from a string
    private nonisolated static func extractFirstWords(from text: String, count: Int) -> String {
        let words = text.split(separator: " ")
        let firstWords = words.prefix(count)
        return firstWords.joined(separator: " ")
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

// MARK: - Idle Unloading

/// Holds a loaded resource only while it's in use, plus an idle grace
/// period. Callers wrap each use in begin() and end(). Concurrent callers
/// share one load, a use that begins during the grace period reuses the
/// loaded resource, and the resource is released once the period passes
/// with nothing in use.
@MainActor
final class IdleUnloader<Resource> {
    private let idleDelay: Duration
    private let load: () async throws -> Resource
    private var loading: Task<Resource, Error>?
    private var unloadTask: Task<Void, Never>?
    private var activeUses = 0

    /// The loaded resource, or nil when unloaded
    private(set) var current: Resource?

    init(idleDelay: Duration, load: @escaping () async throws -> Resource) {
        self.idleDelay = idleDelay
        self.load = load
    }

    /// Starts a use and returns the resource, loading it if needed. Pair
    /// every successful call with end(). On a failed load the use is ended
    /// here, so the caller doesn't call end().
    func begin() async throws -> Resource {
        activeUses += 1
        unloadTask?.cancel()
        unloadTask = nil
        do {
            return try await loaded()
        } catch {
            end()
            throw error
        }
    }

    /// Ends a use. When none remain, the resource is released after the idle delay.
    func end() {
        activeUses = max(0, activeUses - 1)
        guard activeUses == 0 else { return }
        unloadTask?.cancel()
        unloadTask = Task { [weak self, idleDelay] in
            try? await Task.sleep(for: idleDelay)
            guard !Task.isCancelled, let self, self.activeUses == 0 else { return }
            self.current = nil
        }
    }

    private func loaded() async throws -> Resource {
        if let current { return current }
        if let loading { return try await loading.value }
        let task = Task { try await load() }
        loading = task
        do {
            let resource = try await task.value
            loading = nil
            current = resource
            return resource
        } catch {
            loading = nil
            throw error
        }
    }
}
