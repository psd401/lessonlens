import XCTest
@testable import LessonLens

@MainActor
final class PauseDetectionTests: XCTestCase {
    private let service = TranscriptionService(config: .load())

    func testGapAtOrAboveThresholdIsDetected() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 3.7, text: "What do you notice about this graph"),
            TranscriptSegment(startTime: 8.82, endTime: 12, text: "It goes up on the right")
        ]
        let pauses = service.detectPauses(in: segments, threshold: 3.0)

        XCTAssertEqual(pauses.count, 1)
        XCTAssertEqual(pauses[0].startTime, 3.7, accuracy: 0.001)
        XCTAssertEqual(pauses[0].endTime, 8.82, accuracy: 0.001)
        XCTAssertEqual(pauses[0].precedingText, "you notice about this graph")
        XCTAssertEqual(pauses[0].followingText, "It goes up on the")
    }

    func testGapBelowThresholdIsIgnored() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "First"),
            TranscriptSegment(startTime: 4.9, endTime: 6, text: "Second")
        ]
        XCTAssertTrue(service.detectPauses(in: segments, threshold: 3.0).isEmpty)
    }

    func testUnsortedSegmentsAreOrderedByStartTime() {
        let segments = [
            TranscriptSegment(startTime: 10, endTime: 12, text: "Third"),
            TranscriptSegment(startTime: 0, endTime: 1, text: "First"),
            TranscriptSegment(startTime: 5, endTime: 6, text: "Second")
        ]
        let pauses = service.detectPauses(in: segments, threshold: 3.0)

        XCTAssertEqual(pauses.map(\.precedingText), ["First", "Second"])
        XCTAssertEqual(pauses.map(\.followingText), ["Second", "Third"])
    }

    func testSingleSegmentHasNoPauses() {
        let segments = [TranscriptSegment(startTime: 0, endTime: 5, text: "Only")]
        XCTAssertTrue(service.detectPauses(in: segments, threshold: 3.0).isEmpty)
    }
}
