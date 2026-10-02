import XCTest
@testable import RunPulse

@MainActor
extension PollerTests {
    func runningThenPushedOffPage() async -> Poller {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "in_progress", nil)])
        let poller = makePoller()
        await poller.tick()
        github.runs["me/a"] = .success([run(2, "completed", "success", updated: 5)])
        return poller
    }

    func testInFlightRunOffPageIsFetchedAndNotifiesOnce() async {
        let poller = await runningThenPushedOffPage()
        github.singleRuns[1] = .success(run(1, "in_progress", nil))
        at(10); await poller.tick()
        XCTAssertEqual(poller.state.running.map(\.id), [1])
        XCTAssertTrue(github.calls.contains("run 1"))
        github.singleRuns[1] = .success(run(1, "completed", "success", updated: 12))
        at(20); await poller.tick()
        XCTAssertEqual(poller.state.running, [])
        XCTAssertEqual(finished.flatMap { $0.0 }.map(\.run.id).filter { $0 == 1 }, [1])
        github.resetCalls()
        at(30); await poller.tick()
        XCTAssertFalse(github.calls.contains("run 1"))
    }

    func testSingleRunNotFoundRemovesIt() async {
        let poller = await runningThenPushedOffPage()
        github.singleRuns[1] = .failure(.noAccess)
        at(10); await poller.tick()
        XCTAssertEqual(poller.state.running, [])
        XCTAssertEqual(poller.state.status, .ok)
        XCTAssertTrue(poller.state.noAccess.isEmpty)
    }

    func testMutingMidFetchDoesNotResurrectRepo() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "in_progress", nil)])
        let gate = Gate()
        github.beforeRuns = { await gate.wait() }
        let poller = makePoller()
        let inFlight = Task { await poller.tick() }
        while !gate.isWaiting { await Task.yield() }
        config.muted = ["me/a"]
        poller.apply(config)
        gate.open()
        await inFlight.value
        XCTAssertEqual(poller.state.running, [])
        XCTAssertEqual(poller.state.activeRepos, [])
    }

    func testTokenChangeClearsCooldownAndNoAccess() async {
        github.repos = .success([.fixture("org/secret", pushedAt: t0)])
        github.runs["org/secret"] = .failure(.noAccess)
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.noAccess, ["org/secret"])
        github.runs["org/secret"] = .success([run(1, "completed", "success", repo: "org/secret", updated: -10)])
        poller.tokenChanged()
        at(1); await poller.tick(force: true)
        XCTAssertEqual(poller.state.noAccess, [])
        XCTAssertEqual(poller.state.recent.map(\.id), [1])
    }

    func testRefreshNowClearingCooldownsRetriesNoAccessRepo() async {
        github.repos = .success([.fixture("org/secret", pushedAt: t0)])
        github.runs["org/secret"] = .failure(.noAccess)
        let poller = makePoller()
        await poller.tick()
        github.runs["org/secret"] = .success([run(1, "completed", "success", repo: "org/secret", updated: -10)])
        at(60)
        poller.refreshNow(clearingCooldowns: true)
        for _ in 0..<200 where poller.state.recent.isEmpty { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(poller.state.noAccess, [])
        XCTAssertEqual(poller.state.recent.map(\.id), [1])
    }

    func testRefreshNowWithoutClearingKeepsCooldown() async {
        github.repos = .success([.fixture("org/secret", pushedAt: t0)])
        github.runs["org/secret"] = .failure(.noAccess)
        let poller = makePoller()
        await poller.tick()
        github.resetCalls()
        at(60)
        await poller.tick(force: true)
        XCTAssertFalse(github.calls.contains("runs org/secret"))
    }

    func testAccountSwitchResetsTracker() async {
        github.repos = .success([.fixture("me/a", pushedAt: t0)])
        github.runs["me/a"] = .success([run(1, "in_progress", nil), run(2, "completed", "success", updated: -10)])
        let poller = makePoller()
        await poller.tick()
        XCTAssertEqual(poller.state.running.map(\.id), [1])
        XCTAssertEqual(poller.state.recent.map(\.id), [2])
        github.login = .success("other")
        github.runs["me/a"] = .success([])
        poller.tokenChanged()
        at(1); await poller.tick(force: true)
        XCTAssertEqual(poller.state.account, "other")
        XCTAssertEqual(poller.state.running, [])
        XCTAssertEqual(poller.state.recent, [])
    }
}
