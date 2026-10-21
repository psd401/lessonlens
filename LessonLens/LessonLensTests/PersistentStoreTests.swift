import XCTest
import SwiftData
@testable import LessonLens

/// Stands in for another unsandboxed app's SwiftData model.
@Model
final class UnrelatedNote {
    var text: String
    init(text: String) { self.text = text }
}

@MainActor
final class PersistentStoreTests: XCTestCase {
    private var appSupport: URL!
    private let fileManager = FileManager.default
    private let schema = Schema([Recording.self, Transcript.self, Analysis.self])

    override func setUp() async throws {
        appSupport = fileManager.temporaryDirectory.appendingPathComponent("PersistentStoreTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appFolder.path)
        try? fileManager.removeItem(at: appSupport)
    }

    private var legacyURL: URL { PersistentStore.legacyStoreURL(in: appSupport) }
    private var storeURL: URL { PersistentStore.storeURL(in: appSupport) }
    private var appFolder: URL { storeURL.deletingLastPathComponent() }

    private func exists(_ base: URL, _ suffix: String = "") -> Bool {
        fileManager.fileExists(atPath: base.path + suffix)
    }

    /// Creates a LessonLens store at `url` holding one recording.
    private func makeLessonLensStore(at url: URL, title: String = "Fictional lesson") throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        container.mainContext.insert(Recording(title: title, audioFilePath: "x.m4a", status: .recorded))
        try container.mainContext.save()
    }

    private func titles(in container: ModelContainer) throws -> [String] {
        try container.mainContext.fetch(FetchDescriptor<Recording>()).map(\.title)
    }

    func testStoreLivesInTheAppFolder() {
        XCTAssertEqual(appFolder.lastPathComponent, "com.peninsula.lessonlens")
        XCTAssertEqual(storeURL.lastPathComponent, "LessonLens.store")
    }

    func testFreshInstallOpensAnEmptyStoreInTheAppFolder() throws {
        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        XCTAssertNil(issue)
        XCTAssertEqual(try titles(in: container), [])
        XCTAssertTrue(exists(storeURL))
    }

    func testLessonLensLegacyStoreMovesWithItsSessions() throws {
        try makeLessonLensStore(at: legacyURL)
        let legacyFiles = PersistentStore.fileSuffixes.filter { exists(legacyURL, $0) }

        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        XCTAssertNil(issue)
        XCTAssertEqual(try titles(in: container), ["Fictional lesson"])
        for suffix in legacyFiles {
            XCTAssertFalse(exists(legacyURL, suffix))
            XCTAssertTrue(exists(storeURL, suffix))
        }
    }

    func testAnotherAppsDefaultStoreIsLeftAlone() throws {
        do {
            let other = Schema([UnrelatedNote.self])
            let container = try ModelContainer(for: other, configurations: ModelConfiguration(schema: other, url: legacyURL))
            container.mainContext.insert(UnrelatedNote(text: "someone else's data"))
            try container.mainContext.save()
        }
        let before = try Data(contentsOf: legacyURL)

        XCTAssertFalse(try PersistentStore.isLessonLensStore(at: legacyURL))
        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        XCTAssertNil(issue)
        XCTAssertEqual(try titles(in: container), [])
        XCTAssertEqual(try Data(contentsOf: legacyURL), before)
    }

    func testExistingStoreInTheAppFolderWinsOverALegacyStore() throws {
        try makeLessonLensStore(at: legacyURL, title: "Legacy lesson")
        try makeLessonLensStore(at: storeURL, title: "Current lesson")

        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        XCTAssertNil(issue)
        XCTAssertEqual(try titles(in: container), ["Current lesson"])
        XCTAssertTrue(exists(legacyURL))
    }

    func testFailedMoveKeepsWorkingFromTheLegacyStore() throws {
        try makeLessonLensStore(at: legacyURL)
        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appFolder.path)

        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        XCTAssertNil(issue)
        XCTAssertEqual(try titles(in: container), ["Fictional lesson"])
        XCTAssertTrue(exists(legacyURL))
        XCTAssertFalse(exists(storeURL), "an empty store at the new path would stop the move being retried")
    }

    func testUnreadableLegacyFileIsLeftUnchanged() throws {
        try Data("not a database".utf8).write(to: legacyURL)

        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        guard case .legacyStoreUnreadable = issue else { return XCTFail("expected legacyStoreUnreadable, got \(String(describing: issue))") }
        XCTAssertEqual(try titles(in: container), [])
        XCTAssertEqual(try String(contentsOf: legacyURL, encoding: .utf8), "not a database")
    }

    func testUnreadableStoreIsSetAsideNotDeleted() throws {
        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try Data("corrupted".utf8).write(to: storeURL)

        let (container, issue) = try PersistentStore.openContainer(schema: schema, appSupport: appSupport)

        guard case .storeSetAside(let backupName) = issue else { return XCTFail("expected storeSetAside, got \(String(describing: issue))") }
        XCTAssertTrue(backupName.hasPrefix("LessonLens-backup-"))
        XCTAssertEqual(try String(contentsOf: appFolder.appendingPathComponent(backupName), encoding: .utf8), "corrupted")
        XCTAssertEqual(try titles(in: container), [])
    }

    func testSetAsideRenamesEveryFileToATimestampedBackup() throws {
        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        for suffix in PersistentStore.fileSuffixes {
            try Data(("current" + suffix).utf8).write(to: URL(fileURLWithPath: storeURL.path + suffix))
        }
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 10, 20)
        (components.hour, components.minute, components.second) = (15, 30, 5)
        let date = Calendar.current.date(from: components)!

        let backupURL = try PersistentStore.setAside(storeURL: storeURL, date: date)

        XCTAssertEqual(backupURL.lastPathComponent, "LessonLens-backup-20261020-153005.store")
        XCTAssertEqual(backupURL.deletingLastPathComponent(), appFolder)
        for suffix in PersistentStore.fileSuffixes {
            XCTAssertFalse(exists(storeURL, suffix))
            XCTAssertEqual(try String(contentsOfFile: backupURL.path + suffix, encoding: .utf8), "current" + suffix)
        }
    }
}
