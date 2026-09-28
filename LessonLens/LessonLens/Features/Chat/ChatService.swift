import Foundation

/// Service for interactive coaching chat via /chat endpoint
@MainActor
final class ChatService: ObservableObject {
    private let config: AppConfiguration

    @Published var isSending = false
    @Published var error: ChatError?

    init(config: AppConfiguration) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Send a chat message with full session context
    func sendMessage(
        transcript: String,
        analysisSummary: String,
        techniqueEvaluationsSummary: String,
        reflectionSummary: String?,
        messages: [ChatMessagePayload],
        techniqueNames: [String],
        sessionToken: String
    ) async throws -> String {
        isSending = true
        error = nil

        defer { isSending = false }

        let url = config.backendURL.appendingPathComponent("chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let requestBody = ChatRequest(
            transcript: transcript,
            analysisSummary: analysisSummary,
            techniqueEvaluationsSummary: techniqueEvaluationsSummary,
            reflectionSummary: reflectionSummary,
            messages: messages,
            techniqueNames: techniqueNames
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            return chatResponse.message
        case 429:
            throw ChatError.rateLimited
        case 401, 403:
            throw ChatError.unauthorized
        case 500...599:
            throw ChatError.serviceUnavailable
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatError.apiError(httpResponse.statusCode, errorMessage)
        }
    }

    // MARK: - Transcript Formatting

    /// Format transcript segments with timestamps and pause markers for chat context
    static func formatTimestampedTranscript(transcript: Transcript) -> String {
        let segments = transcript.segments.sorted { $0.startTime < $1.startTime }
        let pauses = transcript.pauses.sorted { $0.startTime < $1.startTime }

        guard !segments.isEmpty else { return transcript.fullText }

        var result: [String] = []
        var pauseIndex = 0

        for segment in segments {
            let startMin = Int(segment.startTime) / 60
            let startSec = Int(segment.startTime) % 60
            let endMin = Int(segment.endTime) / 60
            let endSec = Int(segment.endTime) % 60

            let timeRange = String(format: "[%d:%02d-%d:%02d]", startMin, startSec, endMin, endSec)
            result.append("\(timeRange) \(segment.text)")

            // Insert pause marker if one follows this segment
            if pauseIndex < pauses.count {
                let pause = pauses[pauseIndex]
                if abs(pause.startTime - segment.endTime) < 0.5 {
                    let duration = String(format: "%.1f", pause.duration)
                    result.append("[\(duration)s pause]")
                    pauseIndex += 1
                }
            }
        }

        return result.joined(separator: " ")
    }

    /// Build a structured summary of technique evaluations for chat context
    static func buildTechniqueEvaluationsSummary(analysis: Analysis) -> String {
        guard let evaluations = analysis.techniqueEvaluations, !evaluations.isEmpty else {
            return "No technique evaluations available."
        }

        var lines: [String] = []
        for eval in evaluations {
            var line = "- \(eval.techniqueName)"
            if let rating = eval.rating, let level = RatingLevel(rawValue: rating) {
                line += " (\(level.displayText), \(rating)/5)"
            }
            if !eval.wasObserved {
                line += " [not observed]"
            }
            line += ": \(eval.feedback)"

            if !eval.evidence.isEmpty {
                line += " Evidence: \(eval.evidence.joined(separator: "; "))"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    /// Build reflection summary for chat context
    static func buildReflectionSummary(reflection: Reflection) -> String? {
        guard reflection.isComplete, !reflection.wasSkipped else { return nil }

        var parts: [String] = []
        if !reflection.whatWentWell.isEmpty {
            parts.append("felt \"\(reflection.whatWentWell)\" went well")
        }
        if !reflection.whatToChange.isEmpty {
            parts.append("would change \"\(reflection.whatToChange)\"")
        }
        if !reflection.focusTechniqueIds.isEmpty {
            let focusNames = reflection.selfRatings
                .filter { reflection.focusTechniqueIds.contains($0.techniqueId) }
                .map { $0.techniqueName }
            if !focusNames.isEmpty {
                parts.append("focusing on: \(focusNames.joined(separator: ", "))")
            }
        }

        guard !parts.isEmpty else { return nil }
        return "\n\n### Teacher's Self-Reflection\nThe teacher reflected that \(parts.joined(separator: ", and "))."
    }
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case networkUnavailable
    case rateLimited
    case unauthorized
    case serviceUnavailable
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network unavailable"
        case .rateLimited:
            return "Chat rate limit exceeded. Please try again later."
        case .unauthorized:
            return "Authentication failed. Please sign in again."
        case .serviceUnavailable:
            return "Coaching chat isn't available right now. Please try again later."
        case .apiError(let code, let message):
            return "Chat error (\(code)): \(message)"
        }
    }
}

// MARK: - Request/Response Models

struct ChatMessagePayload: Codable {
    let role: String
    let content: String
}

private struct ChatRequest: Codable {
    let transcript: String
    let analysisSummary: String
    let techniqueEvaluationsSummary: String
    let reflectionSummary: String?
    let messages: [ChatMessagePayload]
    let techniqueNames: [String]

    enum CodingKeys: String, CodingKey {
        case transcript
        case analysisSummary = "analysis_summary"
        case techniqueEvaluationsSummary = "technique_evaluations_summary"
        case reflectionSummary = "reflection_summary"
        case messages
        case techniqueNames = "technique_names"
    }
}

private struct ChatResponse: Codable {
    let message: String
}
