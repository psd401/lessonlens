import XCTest
@testable import LessonLens

/// Review finding PERF-02: the Whisper model (several GB) stayed loaded until
/// the app quit. IdleUnloader holds it only while transcriptions run, plus a
/// grace period.
@MainActor
final class IdleUnloaderTests: XCTestCase {
    private final class Model {}

    private var loads = 0

    private func unloader(delay: Duration = .milliseconds(100), fail: Bool = false) -> IdleUnloader<Model> {
        IdleUnloader(idleDelay: delay) { [unowned self] in
            self.loads += 1
            try await Task.sleep(for: .milliseconds(20))
            if fail { throw CocoaError(.fileReadUnknown) }
            return Model()
        }
    }

    private func wait(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    func testUnloadsAfterTheIdleDelay() async throws {
        let unloader = unloader()
        _ = try await unloader.begin()
        unloader.end()
        XCTAssertNotNil(unloader.current, "kept during the grace period")

        await wait(.milliseconds(300))
        XCTAssertNil(unloader.current)
    }

    func testAUseDuringTheGracePeriodReusesTheModel() async throws {
        let unloader = unloader()
        let first = try await unloader.begin()
        unloader.end()
        await wait(.milliseconds(30))

        let second = try await unloader.begin()
        XCTAssertTrue(first === second)
        XCTAssertEqual(loads, 1)

        await wait(.milliseconds(300))
        XCTAssertNotNil(unloader.current, "still in use, so not unloaded")
        unloader.end()
    }

    func testConcurrentUsesShareOneLoad() async throws {
        let unloader = unloader()
        async let a = unloader.begin()
        async let b = unloader.begin()
        let (first, second) = try await (a, b)

        XCTAssertTrue(first === second)
        XCTAssertEqual(loads, 1)
        unloader.end()
        unloader.end()
    }

    func testItStaysLoadedUntilTheLastUseEnds() async throws {
        let unloader = unloader()
        _ = try await unloader.begin()
        _ = try await unloader.begin()
        unloader.end()

        await wait(.milliseconds(300))
        XCTAssertNotNil(unloader.current)

        unloader.end()
        await wait(.milliseconds(300))
        XCTAssertNil(unloader.current)
    }

    func testAFailedLoadEndsItsUseAndTheNextUseRetries() async throws {
        let failing = unloader(fail: true)
        do {
            _ = try await failing.begin()
            XCTFail("expected the load to fail")
        } catch {}
        XCTAssertNil(failing.current)

        do { _ = try await failing.begin() } catch {}
        XCTAssertEqual(loads, 2, "a failed load isn't cached")
    }

    func testReloadsAfterUnloading() async throws {
        let unloader = unloader()
        _ = try await unloader.begin()
        unloader.end()
        await wait(.milliseconds(300))

        _ = try await unloader.begin()
        XCTAssertEqual(loads, 2)
        unloader.end()
    }
}
