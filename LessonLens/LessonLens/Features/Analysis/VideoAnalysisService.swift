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

/// Service for uploading videos directly to Gemini and requesting analysis
@MainActor
final class VideoAnalysisService: ObservableObject {
    private let config: AppConfiguration
    private var analysisTask: Task<Analysis, Error>?

    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var error: VideoAnalysisError?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Analyzes a video using Gemini via direct upload
    func analyzeVideo(
        videoURL: URL,
        techniques: [Technique],
        sessionToken: String,
        includeRatings: Bool = true
    ) async throws -> Analysis {
        isUploading = true
        uploadProgress = 0
        progress = 0
        error = nil

        do {
            // 1. Initiate upload - get Gemini upload URL from backend
            let initiateResponse = try await initiateUpload(
                fileName: videoURL.lastPathComponent,
                contentType: mimeType(for: videoURL),
                fileSize: fileSize(at: videoURL),
                sessionToken: sessionToken
            )

            uploadProgress = 0.05

            // 2. Upload video directly to Gemini
            let geminiFileName = try await uploadToGemini(
                fileURL: videoURL,
                uploadURL: initiateResponse.uploadUrl,
                contentType: mimeType(for: videoURL)
            )

            isUploading = false
            uploadProgress = 1.0
            isAnalyzing = true
            progress = 0.2

            // 3. Request video analysis from backend
            analysisTask = Task {
                try await performVideoAnalysis(
                    geminiFileName: geminiFileName,
                    techniques: techniques,
                    sessionToken: sessionToken,
                    includeRatings: includeRatings
                )
            }

            let analysis = try await analysisTask!.value
            isAnalyzing = false
            progress = 1.0
            return analysis

        } catch is CancellationError {
            isUploading = false
            isAnalyzing = false
            throw VideoAnalysisError.cancelled
        } catch let error as VideoAnalysisError {
            isUploading = false
            isAnalyzing = false
            self.error = error
            throw error
        } catch {
            isUploading = false
            isAnalyzing = false
            let videoError = VideoAnalysisError.apiError(500, error.localizedDescription)
            self.error = videoError
            throw videoError
        }
    }

    /// Cancels the current analysis
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isUploading = false
        isAnalyzing = false
        uploadProgress = 0
        progress = 0
    }

    // MARK: - Private Methods

    private func initiateUpload(
        fileName: String,
        contentType: String,
        fileSize: Int64,
        sessionToken: String
    ) async throws -> InitiateUploadResponse {
        let url = config.backendURL.appendingPathComponent("upload/initiate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        let requestBody = InitiateUploadRequest(
            fileName: fileName,
            contentType: contentType,
            fileSize: fileSize
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoAnalysisError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(InitiateUploadResponse.self, from: data)
        case 401, 403:
            throw VideoAnalysisError.apiError(httpResponse.statusCode, "Authentication failed")
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VideoAnalysisError.apiError(httpResponse.statusCode, errorMessage)
        }
    }

    private func uploadToGemini(
        fileURL: URL,
        uploadURL: String,
        contentType: String
    ) async throws -> String {
        guard let url = URL(string: uploadURL) else {
            throw VideoAnalysisError.invalidResponse
        }

        // Read file data
        let fileData = try Data(contentsOf: fileURL)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(String(fileData.count), forHTTPHeaderField: "Content-Length")
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")

        // Upload with progress tracking
        let (data, response) = try await uploadWithProgress(request: request, data: fileData)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw VideoAnalysisError.uploadFailed
        }

        // Parse the response to get the file name
        let uploadResponse = try JSONDecoder().decode(GeminiUploadResponse.self, from: data)
        return uploadResponse.file.name
    }

    private func uploadWithProgress(request: URLRequest, data: Data) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            var request = request
            request.httpBody = data

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: VideoAnalysisError.uploadFailed)
                    return
                }
                continuation.resume(returning: (data, response))
            }

            // Track upload progress via observation
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                Task { @MainActor in
                    // Scale progress from 0.05 to 1.0 (0.05 was initiating upload)
                    self.uploadProgress = 0.05 + (progress.fractionCompleted * 0.95)
                }
            }

            task.resume()

            // Clean up observation when done
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                observation.invalidate()
            }
        }
    }

    private func performVideoAnalysis(
        geminiFileName: String,
        techniques: [Technique],
        sessionToken: String,
        includeRatings: Bool
    ) async throws -> Analysis {
        let url = config.backendURL.appendingPathComponent("analyze/video")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600  // 10 minutes for video processing

        let requestBody = VideoAnalysisRequest(
            geminiFileName: geminiFileName,
            techniques: techniques.map { TechniqueDefinition(from: $0) },
            includeRatings: includeRatings
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        progress = 0.3

        let (data, response) = try await URLSession.shared.data(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoAnalysisError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            progress = 0.9
            return try parseAnalysisResponse(data: data, techniques: techniques, ratingsIncluded: includeRatings)
        case 429:
            throw VideoAnalysisError.rateLimited
        case 401, 403:
            throw VideoAnalysisError.apiError(httpResponse.statusCode, "Authentication failed")
        case 500...599:
            throw VideoAnalysisError.serviceUnavailable
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VideoAnalysisError.apiError(httpResponse.statusCode, errorMessage)
        }
    }

    private func parseAnalysisResponse(data: Data, techniques: [Technique], ratingsIncluded: Bool) throws -> Analysis {
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

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "webm": return "video/webm"
        default: return "video/mp4"
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}

// MARK: - Request/Response Models

private struct InitiateUploadRequest: Codable {
    let fileName: String
    let contentType: String
    let fileSize: Int64
}

private struct InitiateUploadResponse: Codable {
    let uploadUrl: String
    let fileDisplayName: String
}

private struct GeminiUploadResponse: Codable {
    let file: GeminiFile

    struct GeminiFile: Codable {
        let name: String
        let displayName: String
        let mimeType: String
        let sizeBytes: String
        let createTime: String
        let updateTime: String
        let expirationTime: String
        let sha256Hash: String
        let uri: String
        let state: String
    }
}

private struct VideoAnalysisRequest: Codable {
    let geminiFileName: String
    let techniques: [TechniqueDefinition]
    let includeRatings: Bool
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
        }
    }
}
