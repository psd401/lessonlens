import XCTest
@testable import LessonLens

@MainActor
final class VideoAnalysisServiceTests: XCTestCase {
    private let techniques = [
        Technique(
            id: "wait-time",
            name: "Wait Time",
            category: .questioning,
            description: "Pause after asking a question",
            lookFors: ["Pauses of 3+ seconds"],
            exemplarPhrases: ["Take a moment to think."]
        )
    ]

    // MARK: - Request body

    func testRequestBodySendsCloudStorageObjectAndRoundedDuration() throws {
        let data = try VideoAnalysisService.analysisRequestBody(
            gcsObject: "uploads/abc/123.mp4",
            techniques: techniques,
            includeRatings: true,
            durationSeconds: 2745.6
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["gcsObject"] as? String, "uploads/abc/123.mp4")
        XCTAssertEqual(json["durationSeconds"] as? Int, 2746)
        XCTAssertEqual(json["includeRatings"] as? Bool, true)
        XCTAssertNil(json["geminiFileName"], "the old Gemini Files API field must not be sent")

        let technique = try XCTUnwrap((json["techniques"] as? [[String: Any]])?.first)
        XCTAssertEqual(technique["id"] as? String, "wait-time")
        XCTAssertEqual(technique["lookFors"] as? [String], ["Pauses of 3+ seconds"])
    }

    func testRequestBodyOmitsDurationWhenUnknown() throws {
        let data = try VideoAnalysisService.analysisRequestBody(
            gcsObject: "uploads/abc/123.mp4",
            techniques: techniques,
            includeRatings: false,
            durationSeconds: nil
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["durationSeconds"])
    }

    // MARK: - Response handling

    func testSuccessfulResponseBecomesAnalysis() throws {
        let body = """
        {"overall_summary": "Clear objective", "strengths": ["Warm opening"], "growth_areas": [],
         "actionable_next_steps": ["Try think-pair-share"], "model_used": "gemini-3.8-flash",
         "technique_evaluations": [{"technique_id": "wait-time", "was_observed": true, "rating": 3,
           "evidence": ["Paused after the question"], "feedback": "Good", "suggestions": []}]}
        """
        let analysis = try VideoAnalysisService.handleAnalysisResponse(
            statusCode: 200, data: Data(body.utf8), techniques: techniques, ratingsIncluded: true
        )

        XCTAssertEqual(analysis.overallSummary, "Clear objective")
        XCTAssertEqual(analysis.techniqueEvaluations?.count, 1)
        XCTAssertEqual(analysis.techniqueEvaluations?.first?.techniqueName, "Wait Time")
    }

    func testVertexRejectionMapsToVideoRejected() {
        let body = #"{"error": "Video analysis service error", "status": 400}"#
        XCTAssertThrowsError(try VideoAnalysisService.handleAnalysisResponse(
            statusCode: 502, data: Data(body.utf8), techniques: techniques, ratingsIncluded: true
        )) { error in
            guard case VideoAnalysisError.videoRejected = error else {
                return XCTFail("expected videoRejected, got \(error)")
            }
        }
    }

    func testOtherUpstreamFailuresMapToServiceUnavailable() {
        for body in [#"{"error": "x", "status": 429}"#, #"{"error": "x"}"#, "not json"] {
            XCTAssertThrowsError(try VideoAnalysisService.handleAnalysisResponse(
                statusCode: 502, data: Data(body.utf8), techniques: techniques, ratingsIncluded: true
            )) { error in
                guard case VideoAnalysisError.serviceUnavailable = error else {
                    return XCTFail("expected serviceUnavailable for \(body), got \(error)")
                }
            }
        }
    }

    func testRateLimitMapsToRateLimited() {
        XCTAssertThrowsError(try VideoAnalysisService.handleAnalysisResponse(
            statusCode: 429, data: Data(), techniques: techniques, ratingsIncluded: true
        )) { error in
            guard case VideoAnalysisError.rateLimited = error else {
                return XCTFail("expected rateLimited, got \(error)")
            }
        }
    }

    // MARK: - Transcript fallback

    func testOnlyVideoSpecificFailuresOfferTranscriptFallback() {
        XCTAssertTrue(VideoAnalysisError.videoRejected.offersTranscriptFallback)
        XCTAssertTrue(VideoAnalysisError.compressedTooLarge.offersTranscriptFallback)
        XCTAssertTrue(VideoAnalysisError.compressionFailed.offersTranscriptFallback)

        XCTAssertFalse(VideoAnalysisError.serviceUnavailable.offersTranscriptFallback)
        XCTAssertFalse(VideoAnalysisError.rateLimited.offersTranscriptFallback)
        XCTAssertFalse(VideoAnalysisError.uploadFailed.offersTranscriptFallback)
        XCTAssertFalse(VideoAnalysisError.networkUnavailable.offersTranscriptFallback)
    }
}
