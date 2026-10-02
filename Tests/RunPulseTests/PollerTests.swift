import XCTest
@testable import RunPulse

@MainActor
final class PollerTests: XCTestCase {
    fileprivate let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    fileprivate var clock = Date(timeIntervalSince1970: 1_800_000_000)
    fileprivate var github: FakeGitHub!
    fileprivate var tokens: FakeTokens!
    fileprivate var config = AppConfig()
    fileprivate var finished: [([FinishedEvent], [String: FailedStep])] = []

    override func setUp() async throws {
        clock = t0
        github = FakeGitHub()
        tokens = FakeTokens()
        config = AppConfig()
        finished = []
    }

    fileprivate func makePoller() -> Poller {
        let poller = Poller(client: github, tokens: tokens, config: config, now: { [unowned self] in self.clock })
        poller.onFinished = { [unowned self] events, details in self.finished.append((events, details)) }
        return poller
    }

    fileprivate func at(_ seconds: TimeInterval) { clock = t0.addingTimeInterval(seconds) }

    fileprivate func run(_ id: Int, _ status: String, _ conclusion: String?, repo: String = "me/a",
                     updated: TimeInterval = 0) -> Run {
        Run.fixture(id: id, repo: repo, status: status, conclusion: conclusion,
                    created: t0.addingTimeInterval(-120), updated: t0.addingTimeInterval(updated))
    }

    func testFirstTickPollsReposInLookback() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0.addingTimeInterval(-86_400)),
                                 .fixture("me/old", pushedAt: t0.addingTimeInterval(-30 * 86_400)),
                                 .fixture("me/archived", pushedAt: t0, archived: true)])
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(github.calls, ["viewer", "repos", "runs me/a"])
        XCTAssertEqual(poller.state.account, "me")
        XCTAssertEqual(poller.state.tokenSource, .gh)
        XCTAssertEqual(poller.state.status, .ok)
        XCTAssertEqual(poller.state.discovered, ["me/a"])
        XCTAssertEqual(poller.state.activeRepos, ["me/a"])
    }

    func testMutedRepoIsSkippedAndCleared() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "completed", "success", updated: -600)])
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.recent.map(\.id), [1])
        config.muted = ["me/a"]
        poller.apply(config)
        XCTAssertEqual(poller.state.recent, [])
        XCTAssertEqual(poller.state.discovered, ["me/a"])
        github.resetCalls()
        at(60)
        await poller.tick()
        XCTAssertEqual(github.calls, ["repos"])
    }

    func testCadenceFastWhileRunningSlowWhenIdle() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "in_progress", nil)])
        let poller = makePoller()
        await poller.tick()
        github.resetCalls()
        at(5); await poller.tick()
        XCTAssertEqual(github.calls, [])
        at(10); await poller.tick()
        XCTAssertEqual(github.calls, ["runs me/a"])
        github.runs["me/a"] = .success([run(1, "completed", "success", updated: 15)])
        at(20); await poller.tick()
        XCTAssertEqual(finished.count, 1)
        github.resetCalls()
        at(30); await poller.tick()
        XCTAssertEqual(github.calls, [])
        at(80); await poller.tick()
        XCTAssertEqual(github.calls, ["repos", "runs me/a"])
    }

    func testFailedRunReportsFailureDetail() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(7, "in_progress", nil)])
        github.steps[7] = FailedStep(job: "build", step: "Run tests")
        let poller = makePoller()
        await poller.tick()
        github.runs["me/a"] = .success([run(7, "completed", "failure", updated: 9)])
        at(10); await poller.tick()
        XCTAssertEqual(finished.first?.0.map(\.run.id), [7])
        XCTAssertEqual(finished.first?.1["7#1"], FailedStep(job: "build", step: "Run tests"))
        XCTAssertEqual(poller.state.failures["7#1"]?.label, "build › Run tests")
        XCTAssertTrue(github.calls.contains("jobs 7"))
    }

    func testNoTokenIsAuthMissingAndBacksOff() async {
        tokens.next = [nil]
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .authMissing)
        XCTAssertEqual(tokens.reads, 1)
        at(5); await poller.tick()
        XCTAssertEqual(tokens.reads, 1)
        at(60); await poller.tick()
        XCTAssertEqual(tokens.reads, 2)
        XCTAssertEqual(github.calls, [])
    }

    func testUnauthorizedRetriesOnceWithFreshToken() async {
        tokens.next = [Token(value: "old", source: .gh), Token(value: "new", source: .keychain)]
        github.unauthorizedTokens = ["old"]
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .ok)
        XCTAssertEqual(poller.state.tokenSource, .keychain)
        XCTAssertEqual(tokens.invalidations, 1)
    }

    func testUnauthorizedWithSameTokenIsAuthFailed() async {
        tokens.next = [Token(value: "old", source: .gh)]
        github.unauthorizedTokens = ["old"]
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .authFailed)
        github.resetCalls()
        at(30); await poller.tick()
        XCTAssertEqual(github.calls, [])
    }

    func testRateLimitPausesUntilReset() async {
        github.repos = .failure(.rateLimited(until: t0.addingTimeInterval(120)))
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .rateLimited(until: t0.addingTimeInterval(120)))
        github.resetCalls()
        at(60); await poller.tick()
        XCTAssertEqual(github.calls, [])
        github.repos = .success([])
        at(121); await poller.tick()
        XCTAssertEqual(github.calls, ["repos"])
        XCTAssertEqual(poller.state.status, .ok)
    }

    func testNoAccessRepoCoolsDown() async {
        github.repos = .success([.fixture("org/secret", pushedAt: t0)])
        github.runs["org/secret"] = .failure(.noAccess)
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .ok)
        XCTAssertEqual(poller.state.noAccess, ["org/secret"])
        github.resetCalls()
        at(60); await poller.tick()
        XCTAssertEqual(github.calls, ["repos"])
        at(3_601); await poller.tick()
        XCTAssertTrue(github.calls.contains("runs org/secret"))
    }

    func testHTTPErrorOnOneRepoDoesNotStaleOthers() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0), .fixture("me/b", pushedAt: t0)])
        github.runs["me/a"] = .failure(.http(500))
        github.runs["me/b"] = .success([run(2, "completed", "success", repo: "me/b", updated: -10)])
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .ok)
        XCTAssertEqual(poller.state.recent.map(\.id), [2])
        github.resetCalls()
        at(5); await poller.tick()
        XCTAssertEqual(github.calls, [])
    }

    func testStaleAfterTwoFailuresKeepsLists() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "completed", "success", updated: -10)])
        let poller = makePoller()
        await poller.tick()
        github.repos = .failure(.unreachable)
        at(60); await poller.tick()
        XCTAssertEqual(poller.state.status, .ok)
        at(120); await poller.tick()
        XCTAssertEqual(poller.state.status, .stale)
        XCTAssertEqual(poller.state.recent.map(\.id), [1])
    }

    func testUnreachableWithoutData() async {
        github.login = .failure(.unreachable)
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.status, .loading)
        at(5); await poller.tick()
        XCTAssertEqual(poller.state.status, .unreachable)
    }

    func testRunningRunKeepsRepoActive() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0.addingTimeInterval(-7 * 86_400 + 1_800))])
        github.runs["me/a"] = .success([run(1, "in_progress", nil)])
        let poller = makePoller()
        await poller.tick()
        github.resetCalls()
        at(3_600); await poller.tick() // repo now outside the 7-day window
        XCTAssertEqual(poller.state.discovered, [])
        XCTAssertTrue(github.calls.contains("runs me/a"))
        XCTAssertEqual(poller.state.activeRepos, ["me/a"])
    }

    func testWakeRebaselinesSilently() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0.addingTimeInterval(3_600))])
        let poller = makePoller()
        at(36_000)
        github.runs["me/a"] = .success([run(1, "completed", "success", updated: 7_200)])
        poller.prepareForWake()
        await poller.tick(force: true)
        XCTAssertTrue(finished.isEmpty)
        XCTAssertEqual(poller.state.recent.map(\.id), [1])
    }

    func testTokenChangeRefetchesViewer() async {
        let poller = makePoller()
        await poller.tick()
        github.resetCalls()
        github.login = .success("other")
        poller.tokenChanged()
        at(1); await poller.tick(force: true)
        XCTAssertEqual(github.calls.first, "viewer")
        XCTAssertEqual(poller.state.account, "other")
    }
}

extension PollerTests {
    // MARK: Fix round 1

    func testTokenChangeMidFlightDoesNotKeepOldAccount() async {
        let gate = Gate()
        github.beforeViewer = { await gate.wait() }
        let poller = makePoller()
        var accounts: [String?] = []
        poller.onUpdate = { accounts.append($0.account) }
        let inFlight = Task { await poller.tick() }
        while !gate.isWaiting { await Task.yield() }
        poller.tokenChanged()
        github.login = .success("other")
        gate.open()
        await inFlight.value
        XCTAssertFalse(accounts.contains("me"))
        XCTAssertEqual(poller.state.account, "other")
        XCTAssertEqual(github.calls.filter { $0 == "viewer" }.count, 2)
    }

    func testAbortedCycleStillPublishesMergedRepos() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0), .fixture("me/b", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "completed", "success", updated: -10)])
        github.runs["me/b"] = .failure(.unreachable)
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.recent.map(\.id), [1])
    }

    func testForcedTickHonoursRateLimitPause() async {
        github.repos = .failure(.rateLimited(until: t0.addingTimeInterval(120)))
        let poller = makePoller()
        await poller.tick()
        github.resetCalls()
        at(60); await poller.tick(force: true)
        XCTAssertEqual(github.calls, [])
    }

    func testForcedRefreshDuringInFlightTickIsNotLost() async {
        let gate = Gate()
        github.beforeViewer = { await gate.wait() }
        let poller = makePoller()
        let inFlight = Task { await poller.tick() }
        while !gate.isWaiting { await Task.yield() }
        await poller.tick(force: true)
        gate.open()
        await inFlight.value
        XCTAssertEqual(github.calls, ["viewer", "repos", "repos"])
    }

    func testNoAccessDropsRunningRunsAndStopsPolling() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "in_progress", nil)])
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.running.map(\.id), [1])
        github.runs["me/a"] = .failure(.noAccess)
        at(10); await poller.tick()
        XCTAssertEqual(poller.state.running, [])
        github.resetCalls()
        at(15); await poller.tick()
        XCTAssertEqual(github.calls, [])
        at(60); await poller.tick()
        XCTAssertEqual(github.calls, ["repos"])
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    var isWaiting: Bool { lock.withLock { continuation != nil } }

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
