import XCTest
@testable import RunPulse

final class RunTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ id: Int, _ status: String = "completed", _ conclusion: String? = "success",
                     repo: String = "me/app", event: String = "push", attempt: Int = 1,
                     created: TimeInterval = 0, updated: TimeInterval = 0) -> Run {
        Run.fixture(id: id, attempt: attempt, repo: repo, event: event, status: status, conclusion: conclusion,
                    created: t0.addingTimeInterval(created), updated: t0.addingTimeInterval(updated))
    }

    func testBaselineIsSilent() {
        var tracker = RunTracker(baselineAt: t0)
        let events = tracker.merge(repo: "me/app", runs: [run(1, updated: -60)])
        XCTAssertEqual(events, [])
        XCTAssertEqual(tracker.recent.map(\.id), [1])
    }

    func testRunFinishedBetweenPollsNotifies() {
        var tracker = RunTracker(baselineAt: t0)
        let finished = run(1, created: 5, updated: 30)
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [finished]), [FinishedEvent(run: finished)])
    }

    func testRunningThenCompletedNotifiesOnce() {
        var tracker = RunTracker(baselineAt: t0)
        _ = tracker.merge(repo: "me/app", runs: [run(1, "in_progress", nil, created: -300, updated: -10)])
        XCTAssertEqual(tracker.running.map(\.id), [1])
        XCTAssertTrue(tracker.hasActiveRuns(repo: "me/app"))
        let done = run(1, "completed", "failure", created: -300, updated: 20)
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [done]), [FinishedEvent(run: done)])
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [done]), [])
        XCTAssertFalse(tracker.hasActiveRuns(repo: "me/app"))
    }

    func testIgnoredEvents() {
        var tracker = RunTracker(baselineAt: t0)
        let runs = [run(1, event: "pull_request", updated: 10), run(2, event: "schedule", updated: 10),
                    run(3, event: "pull_request_target", updated: 10), run(4, event: "workflow_dispatch", updated: 10)]
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: runs).map(\.run.id), [4])
        XCTAssertEqual(tracker.recent.map(\.id), [4])
    }

    func testReRunNotifiesAgain() {
        var tracker = RunTracker(baselineAt: t0)
        _ = tracker.merge(repo: "me/app", runs: [run(1, "in_progress", nil)])
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [run(1, "completed", "failure", updated: 60)]).count, 1)
        _ = tracker.merge(repo: "me/app", runs: [run(1, "queued", nil, attempt: 2, updated: 120)])
        XCTAssertEqual(tracker.running.map(\.key), ["1#2"])
        let rerun = run(1, "completed", "success", attempt: 2, updated: 200)
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [rerun]), [FinishedEvent(run: rerun)])
    }

    func testReRunFinishedBetweenPollsNotifies() {
        var tracker = RunTracker(baselineAt: t0)
        _ = tracker.merge(repo: "me/app", runs: [run(1, updated: -60)]) // baseline, silent
        let rerun = run(1, "completed", "success", attempt: 2, updated: 30)
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [rerun]), [FinishedEvent(run: rerun)])
    }

    func testRecentAndRunningOrdering() {
        var tracker = RunTracker(baselineAt: t0)
        let completed = (1...12).map { run($0, updated: TimeInterval(-$0 * 60)) }
        _ = tracker.merge(repo: "me/app", runs: completed)
        XCTAssertEqual(tracker.recent.map(\.id), Array(1...10))
        _ = tracker.merge(repo: "me/other", runs: [run(20, "in_progress", nil, repo: "me/other", created: -100),
                                                    run(21, "queued", nil, repo: "me/other", created: -10)])
        XCTAssertEqual(tracker.running.map(\.id), [21, 20])
        XCTAssertEqual(tracker.reposWithActiveRuns, ["me/other"])
    }

    func testRebaselineSilencesOlderFinishes() {
        var tracker = RunTracker(baselineAt: t0)
        tracker.rebaseline(at: t0.addingTimeInterval(36_000 - 600))
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [run(1, updated: 7_200)]), [])
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: [run(1, updated: 7_200), run(2, updated: 35_900)]).count, 1)
    }

    func testRemoveRepoAndDropMissingRuns() {
        var tracker = RunTracker(baselineAt: t0)
        _ = tracker.merge(repo: "me/app", runs: [run(1, updated: -10), run(2, updated: -20)])
        _ = tracker.merge(repo: "me/other", runs: [run(3, repo: "me/other", updated: -30)])
        _ = tracker.merge(repo: "me/app", runs: [run(1, updated: -10)])
        XCTAssertEqual(tracker.recent.map(\.id), [1, 3])
        tracker.remove(repo: "me/other")
        XCTAssertEqual(tracker.recent.map(\.id), [1])
    }

    func testNotifiedSetIsCapped() {
        var tracker = RunTracker(baselineAt: t0)
        let runs = (1...501).map { run($0, updated: 10) }
        XCTAssertEqual(tracker.merge(repo: "me/app", runs: runs).count, 501)
        XCTAssertEqual(tracker.notifiedCount, RunTracker.notifiedLimit)
    }

    func testEqualTimestampsOrderDeterministicallyByID() {
        var tracker = RunTracker(baselineAt: t0)
        let ids = Array(1...12)
        let events = tracker.merge(repo: "me/app", runs: ids.map { run($0, created: 5, updated: 30) })
        XCTAssertEqual(events.map(\.run.id), ids)
        XCTAssertEqual(tracker.recent.map(\.id), Array(ids.reversed().prefix(RunTracker.recentLimit)))
        var live = RunTracker(baselineAt: t0)
        _ = live.merge(repo: "me/app", runs: ids.map { run($0, "in_progress", nil, created: 5, updated: 5) })
        XCTAssertEqual(live.running.map(\.id), ids.reversed())
    }
}
