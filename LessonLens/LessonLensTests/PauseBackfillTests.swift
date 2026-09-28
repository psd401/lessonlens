import XCTest
import SwiftData
@testable import LessonLens

@MainActor
final class PauseBackfillTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Recording.self, Transcript.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private let segmentsWithGap = [
        TranscriptSegment(startTime: 0, endTime: 3.7, text: "What do you notice about this graph"),
        TranscriptSegment(startTime: 8.82, endTime: 12, text: "It goes up on the right")
    ]

    func testTranscriptMissingPausesIsBackfilled() throws {
        let transcript = Transcript(fullText: "", modelUsed: "test", segments: segmentsWithGap)
        context.insert(transcript)

        XCTAssertEqual(TranscriptionService.backfillMissingPauses(in: context), 1)
        XCTAssertEqual(transcript.pauses.count, 1)
        XCTAssertEqual(transcript.pauses[0].startTime, 3.7, accuracy: 0.001)
        XCTAssertEqual(transcript.pauses[0].endTime, 8.82, accuracy: 0.001)
    }

    func testExistingPausesAreLeftAlone() throws {
        let existing = TranscriptPause(startTime: 3.7, endTime: 8.82, precedingText: "a", followingText: "b")
        let transcript = Transcript(fullText: "", modelUsed: "test", segments: segmentsWithGap, pauses: [existing])
        context.insert(transcript)

        XCTAssertEqual(TranscriptionService.backfillMissingPauses(in: context), 0)
        XCTAssertEqual(transcript.pauses.map(\.id), [existing.id])
    }

    func testTranscriptWithoutQualifyingGapsIsNotCounted() throws {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "First"),
            TranscriptSegment(startTime: 2.5, endTime: 4, text: "Second")
        ]
        let transcript = Transcript(fullText: "", modelUsed: "test", segments: segments)
        context.insert(transcript)

        XCTAssertEqual(TranscriptionService.backfillMissingPauses(in: context), 0)
        XCTAssertTrue(transcript.pauses.isEmpty)
    }

    func testSecondRunChangesNothing() throws {
        let transcript = Transcript(fullText: "", modelUsed: "test", segments: segmentsWithGap)
        context.insert(transcript)

        TranscriptionService.backfillMissingPauses(in: context)
        let ids = transcript.pauses.map(\.id)

        XCTAssertEqual(TranscriptionService.backfillMissingPauses(in: context), 0)
        XCTAssertEqual(transcript.pauses.map(\.id), ids)
    }
}
