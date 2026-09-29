import XCTest
import SwiftData
@testable import LessonLens

@MainActor
final class InterruptedProcessingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Recording.self, Transcript.self, Analysis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func recording(_ status: RecordingStatus, transcript: Bool = false, analysis: Bool = false) -> Recording {
        let recording = Recording(title: "Fictional lesson", audioFilePath: "x.m4a", status: status)
        context.insert(recording)
        if transcript {
            recording.transcript = Transcript(fullText: "Hello class", modelUsed: "test", segments: [])
        }
        if analysis {
            recording.analysis = Analysis(overallSummary: "Summary", modelUsed: "test")
        }
        return recording
    }

    func testMidProcessRecordingsFallBackToLastFinishedStep() {
        let uploading = recording(.uploading)
        let transcribing = recording(.transcribing)
        let analyzingWithTranscript = recording(.analyzing, transcript: true)
        let analyzingWithAnalysis = recording(.analyzing, transcript: true, analysis: true)

        XCTAssertEqual(Recording.resetInterruptedProcessing(in: context), 4)
        XCTAssertEqual(uploading.status, .recorded)
        XCTAssertEqual(transcribing.status, .recorded)
        XCTAssertEqual(analyzingWithTranscript.status, .transcribed)
        XCTAssertEqual(analyzingWithAnalysis.status, .complete)
    }

    func testSettledRecordingsAreLeftAlone() {
        let recorded = recording(.recorded)
        let transcribed = recording(.transcribed, transcript: true)
        let complete = recording(.complete, transcript: true, analysis: true)
        let live = recording(.recording)

        XCTAssertEqual(Recording.resetInterruptedProcessing(in: context), 0)
        XCTAssertEqual(recorded.status, .recorded)
        XCTAssertEqual(transcribed.status, .transcribed)
        XCTAssertEqual(complete.status, .complete)
        XCTAssertEqual(live.status, .recording)
    }
}
