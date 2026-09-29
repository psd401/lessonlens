import Foundation

/// Defines the analysis method for video recordings
enum VideoAnalysisMethod: String, CaseIterable {
    case geminiVideo = "gemini"        // Full video analysis with Gemini
    case geminiText = "gemini-text"    // Extract audio, transcribe, analyze with Gemini

    var displayName: String {
        switch self {
        case .geminiVideo: return "Video Analysis (Gemini)"
        case .geminiText: return "Audio Only (Gemini)"
        }
    }

    var description: String {
        switch self {
        case .geminiVideo: return "Analyzes visual + audio content"
        case .geminiText: return "Extracts audio, transcribes"
        }
    }

    var estimatedCost: String {
        switch self {
        case .geminiVideo: return "~$0.15-0.27"
        case .geminiText: return "~$0.01-0.03"
        }
    }
}

/// Service for uploading videos and requesting Gemini analysis.
///
/// Flow: compress to a 720p copy, upload it to the district's temporary
/// Cloud Storage bucket through a backend-issued upload URL, then ask the
/// backend to analyze it on Vertex AI. The backend deletes the upload after
/// analysis; this service deletes the local copy.
@MainActor
final class VideoAnalysisService: ObservableObject {
    /// The backend and Cloud Storage path accept uploads up to 2GB
    static let maxUploadSize: Int64 = 2 * 1024 * 1024 * 1024

    private let config: AppConfiguration
    private let compressor = VideoCompressionService()
    private var analysisTask: Task<Analysis, Error>?

    @Published var uploadProgress: Double = 0
    @Published var isCompressing = false
    @Published var isUploading = false
    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var error: VideoAnalysisError?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Compresses, uploads and analyzes a video.
    /// - Parameters:
    ///   - durationSeconds: The recording's length; lets the backend sample long videos at a lower frame rate
    ///   - onUploadComplete: Called once the upload finishes and analysis starts
    func analyzeVideo(
        videoURL: URL,
        techniques: [Technique],
        sessionToken: String,
        includeRatings: Bool = true,
        durationSeconds: TimeInterval? = nil,
        onUploadComplete: @escaping @MainActor () -> Void = {}
    ) async throws -> Analysis {
        isUploading = true
        uploadProgress = 0
        progress = 0
        error = nil

        var compressedURL: URL?
        defer {
            if let compressedURL {
                compressor.removeCompressedCopy(compressedURL)
            }
        }

        do {
            // 1. Compress to a 720p copy (first 30% of the upload bar)
            isCompressing = true
            let uploadURL: URL
            do {
                uploadURL = try await compressor.compressForUpload(videoURL) { [weak self] fraction in
                    self?.uploadProgress = 0.3 * fraction
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw VideoAnalysisError.compressionFailed
            }
            compressedURL = uploadURL
            isCompressing = false

            let size = fileSize(at: uploadURL)
            guard size > 0 else {
                throw VideoAnalysisError.compressionFailed
            }
            guard size <= Self.maxUploadSize else {
                throw VideoAnalysisError.compressedTooLarge
            }

            // 2. Get a Cloud Storage upload URL from the backend
            let initiateResponse = try await initiateUpload(
                contentType: "video/mp4",
                fileSize: size,
                sessionToken: sessionToken
            )
            uploadProgress = 0.3

            // 3. Upload the copy, streaming from disk
            try await upload(fileURL: uploadURL, to: initiateResponse.uploadUrl, contentType: "video/mp4")

            isUploading = false
            uploadProgress = 1.0
            onUploadComplete()
            isAnalyzing = true
            progress = 0.2

            // 4. Request video analysis from backend
            analysisTask = Task {
                try await performVideoAnalysis(
                    gcsObject: initiateResponse.objectName,
                    techniques: techniques,
                    sessionToken: sessionToken,
                    includeRatings: includeRatings,
                    durationSeconds: durationSeconds
                )
            }

            let analysis = try await analysisTask!.value
            isAnalyzing = false
            progress = 1.0
            return analysis

        } catch is CancellationError {
            resetState()
            throw VideoAnalysisError.cancelled
        } catch let error as VideoAnalysisError {
            resetState()
            self.error = error
            throw error
        } catch {
            resetState()
            let videoError = VideoAnalysisError.apiError(500, error.localizedDescription)
            self.error = videoError
            throw videoError
        }
    }

    /// Cancels the current analysis
    func cancelAnalysis() {
        compressor.cancel()
        analysisTask?.cancel()
        analysisTask = nil
        resetState()
        uploadProgress = 0
        progress = 0
    }

    // MARK: - Private Methods

    private func resetState() {
        isCompressing = false
        isUploading = false
        isAnalyzing = false
    }

    private func initiateUpload(
        contentType: String,
        fileSize: Int64,
        sessionToken: String
    ) async throws -> InitiateUploadResponse {
        let url = config.backendURL.appendingPathComponent("upload/initiate/gcs")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            InitiateUploadRequest(contentType: contentType, fileSize: fileSize)
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoAnalysisError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(InitiateUploadResponse.self, from: data)
        case 401, 403:
            throw VideoAnalysisError.apiError(httpResponse.statusCode, "Authentication failed")
        case 500...599:
            throw VideoAnalysisError.serviceUnavailable
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VideoAnalysisError.apiError(httpResponse.statusCode, errorMessage)
        }
    }

    /// PUTs the file to the Cloud Storage upload URL, reading from disk rather
    /// than loading the whole video into memory
    private func upload(fileURL: URL, to uploadURL: String, contentType: String) async throws {
        guard let url = URL(string: uploadURL) else {
            throw VideoAnalysisError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate { [weak self] fraction in
            Task { @MainActor in
                // Upload fills 30%-100% of the upload bar
                self?.uploadProgress = 0.3 + 0.7 * fraction
            }
        }

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw VideoAnalysisError.uploadFailed
        }
    }

    private func performVideoAnalysis(
        gcsObject: String,
        techniques: [Technique],
        sessionToken: String,
        includeRatings: Bool,
        durationSeconds: TimeInterval?
    ) async throws -> Analysis {
        let url = config.backendURL.appendingPathComponent("analyze/video")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600  // 10 minutes for video processing

        request.httpBody = try Self.analysisRequestBody(
            gcsObject: gcsObject,
            techniques: techniques,
            includeRatings: includeRatings,
            durationSeconds: durationSeconds
        )

        progress = 0.3

        let (data, response) = try await URLSession.shared.data(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoAnalysisError.networkUnavailable
        }

        progress = 0.9
        return try Self.handleAnalysisResponse(
            statusCode: httpResponse.statusCode,
            data: data,
            techniques: techniques,
            ratingsIncluded: includeRatings
        )
    }

    /// JSON body for /analyze/video
    static func analysisRequestBody(
        gcsObject: String,
        techniques: [Technique],
        includeRatings: Bool,
        durationSeconds: TimeInterval?
    ) throws -> Data {
        try JSONEncoder().encode(VideoAnalysisRequest(
            gcsObject: gcsObject,
            techniques: techniques.map { TechniqueDefinition(from: $0) },
            includeRatings: includeRatings,
            durationSeconds: durationSeconds.map { Int($0.rounded()) }
        ))
    }

    /// Maps the backend's /analyze/video reply to an Analysis or an error
    static func handleAnalysisResponse(
        statusCode: Int,
        data: Data,
        techniques: [Technique],
        ratingsIncluded: Bool
    ) throws -> Analysis {
        switch statusCode {
        case 200:
            return try parseAnalysisResponse(data: data, techniques: techniques, ratingsIncluded: ratingsIncluded)
        case 429:
            throw VideoAnalysisError.rateLimited
        case 401, 403:
            throw VideoAnalysisError.apiError(statusCode, "Authentication failed")
        case 502:
            // The backend passes on Vertex AI's status; 400 means Vertex rejected
            // the video itself (for example, too long for the model)
            let upstream = try? JSONDecoder().decode(UpstreamErrorResponse.self, from: data)
            if upstream?.status == 400 {
                throw VideoAnalysisError.videoRejected
            }
            throw VideoAnalysisError.serviceUnavailable
        case 500...599:
            throw VideoAnalysisError.serviceUnavailable
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VideoAnalysisError.apiError(statusCode, errorMessage)
        }
    }

    private static func parseAnalysisResponse(data: Data, techniques: [Technique], ratingsIncluded: Bool) throws -> Analysis {
        let response = try JSONDecoder().decode(VideoAnalysisResponse.self, from: data)

        let analysis = Analysis(
            overallSummary: response.overallSummary,
            modelUsed: response.modelUsed,
            strengths: response.strengths,
            growthAreas: response.growthAreas,
            actionableNextSteps: response.actionableNextSteps,
            ratingsIncluded: ratingsIncluded
        )

        // Create technique evaluations
        var evaluations: [TechniqueEvaluation] = []
        for evalResponse in response.techniqueEvaluations {
            let technique = techniques.first { $0.id == evalResponse.techniqueId }
            let evaluation = TechniqueEvaluation(
                techniqueId: evalResponse.techniqueId,
                techniqueName: technique?.name ?? evalResponse.techniqueId,
                rating: evalResponse.rating,
                feedback: evalResponse.feedback,
                wasObserved: evalResponse.wasObserved,
                evidence: evalResponse.evidence,
                suggestions: evalResponse.suggestions
            )
            evaluations.append(evaluation)
        }
        analysis.techniqueEvaluations = evaluations

        return analysis
    }

    // MARK: - Helpers

    private func fileSize(at url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}

/// Reports upload progress for one URLSession task
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - Request/Response Models

private struct InitiateUploadRequest: Codable {
    let contentType: String
    let fileSize: Int64
}

private struct InitiateUploadResponse: Codable {
    let uploadUrl: String
    let objectName: String
}

private struct VideoAnalysisRequest: Codable {
    let gcsObject: String
    let techniques: [TechniqueDefinition]
    let includeRatings: Bool
    let durationSeconds: Int?
}

private struct TechniqueDefinition: Codable {
    let id: String
    let name: String
    let description: String
    let lookFors: [String]
    let exemplarPhrases: [String]

    init(from technique: Technique) {
        self.id = technique.id
        self.name = technique.name
        self.description = technique.descriptionText
        self.lookFors = technique.lookFors
        self.exemplarPhrases = technique.exemplarPhrases
    }
}

private struct UpstreamErrorResponse: Codable {
    let status: Int?
}

private struct VideoAnalysisResponse: Codable {
    let overallSummary: String
    let strengths: [String]
    let growthAreas: [String]
    let actionableNextSteps: [String]
    let techniqueEvaluations: [TechniqueEvaluationResponse]
    let modelUsed: String

    enum CodingKeys: String, CodingKey {
        case overallSummary = "overall_summary"
        case strengths
        case growthAreas = "growth_areas"
        case actionableNextSteps = "actionable_next_steps"
        case techniqueEvaluations = "technique_evaluations"
        case modelUsed = "model_used"
    }
}

private struct TechniqueEvaluationResponse: Codable {
    let techniqueId: String
    let wasObserved: Bool
    let rating: Int?
    let evidence: [String]
    let feedback: String
    let suggestions: [String]

    enum CodingKeys: String, CodingKey {
        case techniqueId = "technique_id"
        case wasObserved = "was_observed"
        case rating
        case evidence
        case feedback
        case suggestions
    }
}

// MARK: - Video Analysis Errors

enum VideoAnalysisError: Error, LocalizedError {
    case apiError(Int, String)
    case rateLimited
    case invalidResponse
    case networkUnavailable
    case uploadFailed
    case serviceUnavailable
    case cancelled
    case compressionFailed
    case compressedTooLarge
    case videoRejected

    /// Errors where video analysis won't work for this recording, but analyzing
    /// its transcript (Audio Only) still can
    var offersTranscriptFallback: Bool {
        switch self {
        case .compressionFailed, .compressedTooLarge, .videoRejected:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .serviceUnavailable:
            return "Analysis isn't available right now. Your recording is saved. Please try again later."
        case .rateLimited:
            return "Video analysis rate limit reached. Maximum 5 per hour."
        case .invalidResponse:
            return "Received invalid response from analysis service"
        case .networkUnavailable:
            return "Network unavailable. Please check your connection."
        case .uploadFailed:
            return "Failed to upload video for analysis"
        case .cancelled:
            return "Analysis was cancelled"
        case .compressionFailed:
            return "LessonLens couldn't prepare this video for upload. You can still get feedback by analyzing its transcript instead."
        case .compressedTooLarge:
            return "This video is too large to upload, even after compressing it. You can still get feedback by analyzing its transcript instead."
        case .videoRejected:
            return "Video Analysis couldn't process this video. It may be too long for the model. You can still get feedback by analyzing its transcript instead."
        }
    }
}
