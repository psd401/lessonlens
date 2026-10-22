import XCTest
import SwiftData
@testable import LessonLens

/// Review finding COR-01: deleting a video session left the original video on
/// disk, and re-extracting audio left the previous .m4a behind.
@MainActor
final class MediaCleanupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var directory: URL!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Recording.self, Transcript.self, Analysis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaCleanupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(_ name: String) {
        FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data("x".utf8))
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    private func videoRecording(audio: String, video: String) -> Recording {
        let recording = Recording(title: "Fictional lesson", audioFilePath: audio, videoFilePath: video, mediaType: .video, status: .transcribed)
        context.insert(recording)
        return recording
    }

    /// Mirrors RecordingDetailView.deleteRecording
    private func delete(_ recording: Recording) throws {
        let files = [recording.audioFilePath, recording.videoFilePath]
        context.delete(recording)
        try context.save()
        Recording.removeUnreferencedMedia(files, in: context, directory: directory)
    }

    func testDeletingAVideoSessionRemovesTheVideoAndTheExtractedAudio() throws {
        makeFile("lesson.mov")
        makeFile("extracted.m4a")
        let recording = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        try context.save()

        try delete(recording)

        XCTAssertFalse(exists("lesson.mov"))
        XCTAssertFalse(exists("extracted.m4a"))
    }

    func testDeletingAnAudioSessionRemovesItsFile() throws {
        makeFile("mic.m4a")
        let recording = Recording(title: "Fictional lesson", audioFilePath: "mic.m4a", status: .transcribed)
        context.insert(recording)
        try context.save()

        try delete(recording)

        XCTAssertFalse(exists("mic.m4a"))
    }

    func testSharedFilesStayUntilTheLastSessionUsingThemIsDeleted() throws {
        makeFile("lesson.mov")
        makeFile("extracted.m4a")
        let original = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        let reanalysis = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        try context.save()

        try delete(original)
        XCTAssertTrue(exists("lesson.mov"))
        XCTAssertTrue(exists("extracted.m4a"))

        try delete(reanalysis)
        XCTAssertFalse(exists("lesson.mov"))
        XCTAssertFalse(exists("extracted.m4a"))
    }

    func testReExtractionRemovesTheOldAudioButNotTheVideo() throws {
        makeFile("lesson.mov")
        makeFile("old.m4a")
        makeFile("new.m4a")
        let recording = videoRecording(audio: "old.m4a", video: "lesson.mov")
        try context.save()

        recording.audioFilePath = "new.m4a"
        try context.save()
        let removed = Recording.removeUnreferencedMedia(["old.m4a"], in: context, directory: directory)

        XCTAssertEqual(removed, ["old.m4a"])
        XCTAssertTrue(exists("lesson.mov"))
        XCTAssertTrue(exists("new.m4a"))
    }

    func testFirstExtractionKeepsTheVideoItReplacesAsAudio() throws {
        // A new video import uses the video itself as its audio until extraction
        makeFile("lesson.mov")
        makeFile("new.m4a")
        let recording = videoRecording(audio: "lesson.mov", video: "lesson.mov")
        try context.save()

        recording.audioFilePath = "new.m4a"
        try context.save()
        Recording.removeUnreferencedMedia(["lesson.mov"], in: context, directory: directory)

        XCTAssertTrue(exists("lesson.mov"))
    }

    func testMissingFilesAndUnsafeNamesAreSkipped() throws {
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: outside.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: outside) }

        let removed = Recording.removeUnreferencedMedia(
            ["already-gone.m4a", "", "../\(outside.lastPathComponent)", nil],
            in: context,
            directory: directory
        )

        XCTAssertEqual(removed, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
