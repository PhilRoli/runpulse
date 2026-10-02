import XCTest
@testable import RunPulse

private final class FakeRunner: ProcessRunning, @unchecked Sendable {
    var results: [String: (status: Int32, output: String)] = [:]
    var delay: TimeInterval = 0
    private(set) var calls: [String] = []

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)? {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        calls.append("\(executable) \(arguments.joined(separator: " "))")
        return results[executable]
    }
}

private final class FakeKeychain: KeychainTokenStoring, @unchecked Sendable {
    var value: String?
    func read() throws -> String? { value }
    func save(_ token: String) throws { value = token }
    func delete() throws { value = nil }
}

final class TokenProviderTests: XCTestCase {
    private let brew = "/opt/homebrew/bin/gh"
    private let local = "/usr/local/bin/gh"

    private func provider(_ runner: FakeRunner, keychain: String? = nil) -> CompositeTokenProvider {
        let store = FakeKeychain()
        store.value = keychain
        return CompositeTokenProvider(gh: GhCLITokenSource(runner: runner), keychain: store)
    }

    func testPathOrder() {
        XCTAssertEqual(GhCLITokenSource.paths, [brew, local])
    }

    func testUsesHomebrewGhFirst() throws {
        let runner = FakeRunner()
        runner.results[brew] = (0, "gho_abc\n")
        XCTAssertEqual(try provider(runner).token(), Token(value: "gho_abc", source: .gh))
        XCTAssertEqual(runner.calls, ["\(brew) auth token"])
    }

    func testFallsBackToUsrLocalGh() throws {
        let runner = FakeRunner()
        runner.results[local] = (0, "gho_local")
        XCTAssertEqual(try provider(runner).token(), Token(value: "gho_local", source: .gh))
    }

    func testGhLoggedOutFallsBackToKeychain() throws {
        let runner = FakeRunner()
        runner.results[brew] = (1, "")
        XCTAssertEqual(try provider(runner, keychain: "ghp_pat").token(), Token(value: "ghp_pat", source: .keychain))
    }

    func testEmptyGhOutputFallsThrough() throws {
        let runner = FakeRunner()
        runner.results[brew] = (0, "  \n")
        XCTAssertEqual(try provider(runner, keychain: "ghp_pat").token().source, .keychain)
    }

    func testMissingEverywhereThrows() {
        XCTAssertThrowsError(try provider(FakeRunner()).token()) { error in
            XCTAssertEqual(error as? TokenError, .missing)
        }
    }

    func testCachesUntilInvalidated() throws {
        let runner = FakeRunner()
        runner.results[brew] = (0, "gho_abc")
        let tokens = provider(runner)
        _ = try tokens.token()
        _ = try tokens.token()
        XCTAssertEqual(runner.calls.count, 1)
        tokens.invalidate()
        _ = try tokens.token()
        XCTAssertEqual(runner.calls.count, 2)
    }

    func testSystemRunnerReturnsNilForMissingExecutable() {
        XCTAssertNil(SystemProcessRunner().run("/nonexistent/gh", ["auth", "token"]))
        XCTAssertEqual(SystemProcessRunner().run("/bin/echo", ["hi"])?.output, "hi\n")
    }

    func testSystemRunnerTimesOutHangingProcess() {
        let start = Date()
        XCTAssertNil(SystemProcessRunner(timeout: 0.5).run("/bin/sleep", ["5"]))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testInvalidateDoesNotBlockOnInFlightResolve() async {
        let runner = FakeRunner()
        runner.delay = 1
        runner.results[brew] = (0, "gho_slow")
        let tokens = provider(runner)
        let resolving = Task.detached { try? tokens.token() }
        while runner.calls.isEmpty { try? await Task.sleep(nanoseconds: 10_000_000) }
        let start = Date()
        tokens.invalidate()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
        _ = await resolving.value
        // The resolve that was in flight during invalidate() must not repopulate the cache.
        runner.delay = 0
        _ = try? tokens.token()
        XCTAssertEqual(runner.calls.count, 2)
    }
}
