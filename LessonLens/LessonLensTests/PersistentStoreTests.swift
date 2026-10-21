import XCTest
import SwiftData
@testable import LessonLens

@MainActor
final class PersistentStoreTests: XCTestCase {
    private var appSupport: URL!
    private let fileManager = FileManager.default

    override func setUp() async throws {
        appSupport = fileManager.temporaryDirectory.appendingPathComponent("PersistentStoreTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fileManager.removeItem(at: appSupport)
    }

    private var legacyURL: URL { appSupport.appendingPathComponent(PersistentStore.legacyStoreName) }
    private var storeURL: URL { PersistentStore.storeURL(in: appSupport) }

    private func writeFiles(at base: URL, contents: String) throws {
        for suffix in PersistentStore.fileSuffixes {
            try Data((contents + suffix).utf8).write(to: URL(fileURLWithPath: base.path + suffix))
        }
    }

    private func exists(_ base: URL, _ suffix: String = "") -> Bool {
        fileManager.fileExists(atPath: base.path + suffix)
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Recording.self, Transcript.self, Analysis.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    func testStoreLivesInTheAppFolder() {
        XCTAssertEqual(storeURL.deletingLastPathComponent().lastPathComponent, "com.peninsula.lessonlens")
        XCTAssertEqual(storeURL.lastPathComponent, "LessonLens.store")
    }

    func testMovesAllLegacyFilesIntoTheAppFolder() throws {
        try writeFiles(at: legacyURL, contents: "legacy")

        XCTAssertTrue(try PersistentStore.moveLegacyStoreIfNeeded(appSupport: appSupport))

        for suffix in PersistentStore.fileSuffixes {
            XCTAssertFalse(exists(legacyURL, suffix))
            XCTAssertEqual(try String(contentsOfFile: storeURL.path + suffix), "legacy" + suffix)
        }
    }

    func testDoesNotMoveWhenTheAppFolderAlreadyHasAStore() throws {
        try writeFiles(at: legacyURL, contents: "legacy")
        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFiles(at: storeURL, contents: "current")

        XCTAssertFalse(try PersistentStore.moveLegacyStoreIfNeeded(appSupport: appSupport))

        XCTAssertEqual(try String(contentsOfFile: legacyURL.path), "legacy")
        XCTAssertEqual(try String(contentsOfFile: storeURL.path), "current")
    }

    func testDoesNothingWithoutALegacyStore() throws {
        XCTAssertFalse(try PersistentStore.moveLegacyStoreIfNeeded(appSupport: appSupport))
        XCTAssertFalse(exists(storeURL))
    }

    func testMovedLegacyStoreKeepsItsSessions() throws {
        do {
            let container = try makeContainer(at: legacyURL)
            container.mainContext.insert(Recording(title: "Fictional lesson", audioFilePath: "x.m4a", status: .recorded))
            try container.mainContext.save()
        }

        XCTAssertTrue(try PersistentStore.moveLegacyStoreIfNeeded(appSupport: appSupport))

        let container = try makeContainer(at: storeURL)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        XCTAssertEqual(recordings.map(\.title), ["Fictional lesson"])
    }

    func testUnreadableLegacyStoreIsPutBackUnchanged() throws {
        try Data("not a database".utf8).write(to: legacyURL)
        XCTAssertTrue(try PersistentStore.moveLegacyStoreIfNeeded(appSupport: appSupport))
        XCTAssertThrowsError(try makeContainer(at: storeURL))

        try PersistentStore.restoreLegacyStore(appSupport: appSupport)

        XCTAssertEqual(try String(contentsOfFile: legacyURL.path), "not a database")
        XCTAssertFalse(exists(storeURL))
    }

    func testSetAsideRenamesEveryFileToATimestampedBackup() throws {
        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFiles(at: storeURL, contents: "current")
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 10, 20)
        (components.hour, components.minute, components.second) = (15, 30, 5)
        let date = Calendar.current.date(from: components)!

        let backupURL = try PersistentStore.setAside(storeURL: storeURL, date: date)

        XCTAssertEqual(backupURL.lastPathComponent, "LessonLens-backup-20261020-153005.store")
        XCTAssertEqual(backupURL.deletingLastPathComponent(), storeURL.deletingLastPathComponent())
        for suffix in PersistentStore.fileSuffixes {
            XCTAssertFalse(exists(storeURL, suffix))
            XCTAssertEqual(try String(contentsOfFile: backupURL.path + suffix), "current" + suffix)
        }
    }
}
