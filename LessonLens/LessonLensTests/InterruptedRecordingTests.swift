import XCTest
import SwiftData
@testable import LessonLens

/// Review finding COR-03: a quit or crash mid-recording left the session
/// stuck at "Recording" forever.
@MainActor
final class InterruptedRecordingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var directory: URL!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Recording.self, Transcript.self, Analysis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterruptedRecordingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func recording(_ file: String, status: RecordingStatus = .recording) -> Recording {
        let recording = Recording(title: "Fictional lesson", audioFilePath: file, status: status)
        context.insert(recording)
        return recording
    }

    /// A silent 16-bit mono PCM WAV file of the given length
    private func writeWAV(_ name: String, seconds: Double, sampleRate: UInt32 = 8000) throws {
        let samples = UInt32(Double(sampleRate) * seconds)
        let dataSize = samples * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        data.append(Data(count: Int(dataSize)))
        try data.write(to: directory.appendingPathComponent(name))
    }

    func testARecordingWithItsAudioBecomesRecordedWithTheFilesDuration() throws {
        try writeWAV("lesson.wav", seconds: 2)
        let stuck = recording("lesson.wav")
        try context.save()

        XCTAssertEqual(Recording.finalizeInterruptedRecordings(in: context, directory: directory), 1)
        XCTAssertEqual(stuck.status, .recorded)
        XCTAssertEqual(stuck.duration, 2, accuracy: 0.05)
    }

    func testAnUnreadableFileIsKeptAndTheSessionShownWithNoDuration() throws {
        // A crash usually leaves the .m4a unplayable
        FileManager.default.createFile(atPath: directory.appendingPathComponent("damaged.m4a").path, contents: Data("not audio".utf8))
        let stuck = recording("damaged.m4a")
        try context.save()

        Recording.finalizeInterruptedRecordings(in: context, directory: directory)

        XCTAssertEqual(stuck.status, .recorded)
        XCTAssertEqual(stuck.duration, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("damaged.m4a").path))
    }

    func testARecordingWhoseAudioIsGoneIsDeleted() throws {
        _ = recording("discarded.m4a")
        try context.save()

        Recording.finalizeInterruptedRecordings(in: context, directory: directory)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recording>()), 0)
    }

    func testRecordingsInOtherStatesAreLeftAlone() throws {
        let recorded = recording("gone-1.m4a", status: .recorded)
        let complete = recording("gone-2.m4a", status: .complete)
        try context.save()

        XCTAssertEqual(Recording.finalizeInterruptedRecordings(in: context, directory: directory), 0)
        XCTAssertEqual(recorded.status, .recorded)
        XCTAssertEqual(complete.status, .complete)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recording>()), 2)
    }
}
