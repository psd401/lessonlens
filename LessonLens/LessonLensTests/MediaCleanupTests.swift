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

    /// What RecordingDetailView.deleteRecording calls
    private func delete(_ recording: Recording) {
        Recording.deleteWithMedia(recording, in: context, directory: directory)
    }

    func testDeletingAVideoSessionRemovesTheVideoAndTheExtractedAudio() throws {
        makeFile("lesson.mov")
        makeFile("extracted.m4a")
        let recording = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        try context.save()

        delete(recording)

        XCTAssertFalse(exists("lesson.mov"))
        XCTAssertFalse(exists("extracted.m4a"))
    }

    func testDeleteReportsSuccess() throws {
        makeFile("mic.m4a")
        let recording = Recording(title: "Fictional lesson", audioFilePath: "mic.m4a", status: .transcribed)
        context.insert(recording)
        try context.save()

        XCTAssertTrue(Recording.deleteWithMedia(recording, in: context, directory: directory))
    }

    func testAFailedDeleteIsRolledBackAndKeepsTheFiles() throws {
        makeFile("lesson.mov")
        makeFile("extracted.m4a")
        let recording = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        try context.save()

        let deleted = Recording.deleteWithMedia(recording, in: context, directory: directory, save: { _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })

        XCTAssertFalse(deleted)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recording>()), 1)
        XCTAssertFalse(context.hasChanges, "nothing left pending for an autosave to complete")
        XCTAssertTrue(exists("lesson.mov"))
        XCTAssertTrue(exists("extracted.m4a"))
    }

    func testDeletingAnAudioSessionRemovesItsFile() throws {
        makeFile("mic.m4a")
        let recording = Recording(title: "Fictional lesson", audioFilePath: "mic.m4a", status: .transcribed)
        context.insert(recording)
        try context.save()

        delete(recording)

        XCTAssertFalse(exists("mic.m4a"))
    }

    func testSharedFilesStayUntilTheLastSessionUsingThemIsDeleted() throws {
        makeFile("lesson.mov")
        makeFile("extracted.m4a")
        let original = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        let reanalysis = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        try context.save()

        delete(original)
        XCTAssertTrue(exists("lesson.mov"))
        XCTAssertTrue(exists("extracted.m4a"))

        delete(reanalysis)
        XCTAssertFalse(exists("lesson.mov"))
        XCTAssertFalse(exists("extracted.m4a"))
    }

    func testReExtractionRemovesTheOldAudioButNotTheVideo() throws {
        makeFile("lesson.mov")
        makeFile("old.m4a")
        makeFile("new.m4a")
        let recording = videoRecording(audio: "old.m4a", video: "lesson.mov")
        try context.save()

        recording.replaceAudioFile(with: "new.m4a", in: context, directory: directory)

        XCTAssertFalse(exists("old.m4a"))
        XCTAssertTrue(exists("lesson.mov"))
        XCTAssertTrue(exists("new.m4a"))
    }

    func testFirstExtractionKeepsTheVideoItReplacesAsAudio() throws {
        // A new video import uses the video itself as its audio until extraction
        makeFile("lesson.mov")
        makeFile("new.m4a")
        let recording = videoRecording(audio: "lesson.mov", video: "lesson.mov")
        try context.save()

        recording.replaceAudioFile(with: "new.m4a", in: context, directory: directory)

        XCTAssertEqual(recording.audioFilePath, "new.m4a")
        XCTAssertTrue(exists("lesson.mov"))
    }

    func testMissingFilesAndUnsafeNamesAreSkipped() throws {
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: outside.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: outside) }

        let removed = Recording.removeUnreferencedMedia(
            ["already-gone.m4a", "", ".", "..", "../\(outside.lastPathComponent)", nil],
            in: context,
            directory: directory
        )

        XCTAssertEqual(removed, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path), "\".\" must not remove the folder itself")
    }

    // MARK: - Remove Unused Files (Settings)

    private func makeOldFile(_ name: String, ageMinutes: Double = 60) throws {
        makeFile(name)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ageMinutes * 60)],
            ofItemAtPath: directory.appendingPathComponent(name).path
        )
    }

    func testUnusedFilesAreFoundAndFilesInUseAreNot() throws {
        try makeOldFile("orphan.mov")
        try makeOldFile("lesson.mov")
        try makeOldFile("extracted.m4a")
        _ = videoRecording(audio: "extracted.m4a", video: "lesson.mov")
        try context.save()

        // Setting dates counts as an attribute change, so look from an hour ahead
        let unused = Recording.unusedMediaFiles(in: context, directory: directory, now: Date().addingTimeInterval(3600))

        XCTAssertEqual(unused?.map(\.name), ["orphan.mov"])
        XCTAssertEqual(unused?.first?.bytes, 1)
    }

    func testRecentFilesAreNotOffered() throws {
        // A recording or extraction may still be writing a new file
        try makeOldFile("just-written.m4a", ageMinutes: 2)

        XCTAssertEqual(Recording.unusedMediaFiles(in: context, directory: directory)?.count, 0)
    }

    func testAFreshImportCopyIsNotOfferedEvenWithAnOldModificationDate() throws {
        // copyItem keeps the source's dates, so a just-imported video can look
        // old before its session is saved
        let source = directory.deletingLastPathComponent().appendingPathComponent("source-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: source.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: source) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86400)], ofItemAtPath: source.path)

        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("imported.mov"))

        XCTAssertEqual(Recording.unusedMediaFiles(in: context, directory: directory)?.count, 0)
    }

    func testFoldersAreNotOffered() throws {
        let folder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: folder.path)

        // An hour from now the folder is old by any date, so only the file-type check skips it
        XCTAssertEqual(Recording.unusedMediaFiles(in: context, directory: directory, now: Date().addingTimeInterval(3600))?.count, 0)
    }

    func testOtherStoreBlocksCleanup() throws {
        let appSupport = directory!
        let folder = appSupport.appendingPathComponent(PersistentStore.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertFalse(PersistentStore.hasOtherStore(appSupport: appSupport))

        // A set-aside backup from a store that wouldn't open
        let backup = folder.appendingPathComponent("LessonLens-backup-2026-10-22-120000.store")
        FileManager.default.createFile(atPath: backup.path, contents: Data())
        XCTAssertTrue(PersistentStore.hasOtherStore(appSupport: appSupport))
        try FileManager.default.removeItem(at: backup)

        // A default.store that can't be read might be LessonLens's
        let legacy = PersistentStore.legacyStoreURL(in: appSupport)
        FileManager.default.createFile(atPath: legacy.path, contents: Data("not a store".utf8))
        XCTAssertTrue(PersistentStore.hasOtherStore(appSupport: appSupport))
    }

    func testUnlistableFolderBlocksCleanup() {
        let missing = directory.appendingPathComponent("no-such-app-support")
        XCTAssertTrue(PersistentStore.hasOtherStore(appSupport: missing))
    }
}
