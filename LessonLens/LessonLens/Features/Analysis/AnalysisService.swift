import Foundation

/// Service for analyzing transcripts using Gemini API via backend proxy
@MainActor
final class AnalysisService: ObservableObject {
    private let config: AppConfiguration
    private var analysisTask: Task<Analysis, Error>?

    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var error: AnalysisError?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Analyzes a transcript for selected teaching techniques
    func analyze(
        transcript: Transcript,
        techniques: [Technique],
        sessionToken: String,
        includeRatings: Bool = true
    ) async throws -> Analysis {
        isAnalyzing = true
        progress = 0
        error = nil

        do {
            analysisTask = Task {
                try await performAnalysis(
                    transcript: transcript,
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
            isAnalyzing = false
            throw AnalysisError.cancelled
        } catch let error as AnalysisError {
            isAnalyzing = false
            self.error = error
            throw error
        } catch {
            isAnalyzing = false
            let analysisError = AnalysisError.apiError(500, error.localizedDescription)
            self.error = analysisError
            throw analysisError
        }
    }

    /// Cancels the current analysis
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        progress = 0
    }

    // MARK: - Private Methods

    private func performAnalysis(
        transcript: Transcript,
        techniques: [Technique],
        sessionToken: String,
        includeRatings: Bool = true
    ) async throws -> Analysis {
        let url = config.backendURL.appendingPathComponent("analyze")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300  // 5 minutes for long transcripts

        // Build request body with optional pause data
        let pauseData = PauseDataRequest(from: transcript.pauses)

        let requestBody = AnalysisRequest(
            transcript: transcript.fullText,
            techniques: techniques.map { TechniqueDefinition(from: $0) },
            includeRatings: includeRatings,
            pauseData: pauseData
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        // Make request with streaming support
        let (data, response) = try await URLSession.shared.data(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            progress = 0.9
            return try parseAnalysisResponse(data: data, techniques: techniques, ratingsIncluded: includeRatings)
        case 429:
            throw AnalysisError.rateLimited
        case 401, 403:
            throw AnalysisError.apiError(httpResponse.statusCode, "Authentication failed")
        case 500...599:
            throw AnalysisError.serviceUnavailable
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalysisError.apiError(httpResponse.statusCode, errorMessage)
        }
    }

    private func parseAnalysisResponse(data: Data, techniques: [Technique], ratingsIncluded: Bool) throws -> Analysis {
        let response = try JSONDecoder().decode(AnalysisResponse.self, from: data)

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

    /// Builds the analysis prompt
    static func buildAnalysisPrompt(transcript: String, techniques: [Technique]) -> String {
        var prompt = """
        You are an expert instructional coach analyzing a teaching session transcript. Your task is to evaluate the teacher's use of specific teaching techniques and provide constructive feedback.

        ## Teaching Session Transcript
        ```
        \(transcript)
        ```

        ## Techniques to Evaluate
        Analyze the transcript for evidence of the following teaching techniques:

        """

        for technique in techniques {
            prompt += """

            ### \(technique.name)
            **Description:** \(technique.descriptionText)

            **Look-fors (observable indicators):**
            \(technique.lookFors.map { "- \($0)" }.joined(separator: "\n"))

            **Exemplar phrases:**
            \(technique.exemplarPhrases.map { "- \"\($0)\"" }.joined(separator: "\n"))

            """
        }

        prompt += """

        ## Response Format
        Provide your analysis as a JSON object with the following structure:
        {
            "overallSummary": "2-3 sentence summary of the teaching session's effectiveness",
            "strengths": ["strength 1", "strength 2", "strength 3"],
            "growthAreas": ["growth area 1", "growth area 2"],
            "actionableNextSteps": ["specific action 1", "specific action 2", "specific action 3"],
            "techniqueEvaluations": [
                {
                    "techniqueId": "technique-id",
                    "wasObserved": true/false,
                    "rating": 1-5 (null if not observed),
                    "evidence": ["specific quote or behavior from transcript"],
                    "feedback": "Detailed feedback about technique usage",
                    "suggestions": ["specific improvement suggestion"]
                }
            ]
        }

        ## Rating Scale
        1 - Developing: Technique not observed or needs significant development
        2 - Emerging: Beginning to implement technique with inconsistent results
        3 - Proficient: Solid implementation of technique with room for refinement
        4 - Accomplished: Effective and consistent use of technique
        5 - Exemplary: Strong, consistent implementation that could serve as a model

        ## Guidelines
        - Be specific and cite evidence from the transcript
        - Provide actionable, growth-oriented feedback
        - Balance recognition of strengths with constructive suggestions
        - If a technique was not observed, set wasObserved to false and rating to null
        - Focus on patterns rather than isolated instances

        Respond ONLY with the JSON object, no additional text.
        """

        return prompt
    }
}

// MARK: - Request/Response Models

private struct AnalysisRequest: Codable {
    let transcript: String
    let techniques: [TechniqueDefinition]
    let includeRatings: Bool
    let pauseData: PauseDataRequest?
}

private struct PauseDataRequest: Codable {
    let pauses: [PauseInfo]
    let summary: PauseSummary

    struct PauseInfo: Codable {
        let startTime: Double
        let endTime: Double
        let duration: Double
        let precedingText: String
        let followingText: String
    }

    struct PauseSummary: Codable {
        let count: Int
        let averageDuration: Double
        let maxDuration: Double
        let totalPauseTime: Double
    }

    init?(from pauses: [TranscriptPause]) {
        guard !pauses.isEmpty else { return nil }

        self.pauses = pauses.map { pause in
            PauseInfo(
                startTime: pause.startTime,
                endTime: pause.endTime,
                duration: pause.duration,
                precedingText: pause.precedingText,
                followingText: pause.followingText
            )
        }

        let totalPauseTime = pauses.reduce(0) { $0 + $1.duration }
        let maxDuration = pauses.map(\.duration).max() ?? 0

        self.summary = PauseSummary(
            count: pauses.count,
            averageDuration: totalPauseTime / Double(pauses.count),
            maxDuration: maxDuration,
            totalPauseTime: totalPauseTime
        )
    }
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

private struct AnalysisResponse: Codable {
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
