import XCTest
@testable import RunPulse

final class MenuModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(_ status: PollStatus = .ok, running: [Run] = [], recent: [Run] = [],
                       failures: [String: FailedStep] = [:], active: [String] = []) -> PollerState {
        var state = PollerState()
        state.status = status
        state.running = running
        state.recent = recent
        state.failures = failures
        state.activeRepos = active
        return state
    }

    func testBlockingMessages() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(MenuModel.rows(state: state(.loading)), [.message("Connecting…")])
        XCTAssertEqual(MenuModel.rows(state: state(.authMissing)), [.message("⚠︎ Run gh auth login")])
        XCTAssertEqual(MenuModel.rows(state: state(.authFailed)), [.message("⚠︎ Token rejected")])
        XCTAssertEqual(MenuModel.rows(state: state(.unreachable)), [.message("⚠︎ GitHub unreachable")])
        XCTAssertEqual(MenuModel.rows(state: state(.rateLimited(until: Date(timeIntervalSince1970: 1_790_958_745))),
                                      timeZone: utc),
                       [.message("⚠︎ Rate limited until 16:32")])
    }

    func testEmptyOK() {
        XCTAssertEqual(MenuModel.rows(state: state()), [.section("Recent"), .message("No recent runs")])
    }

    func testRunningRecentAndActions() {
        let running = Run.fixture(id: 1, repo: "PhilRoli/rettstat", workflow: "Deploy develop", branch: "develop",
                                  status: "in_progress", conclusion: nil, created: t0, started: t0)
        let failed = Run.fixture(id: 2, repo: "PhilRoli/rettstat", workflow: "Deploy develop", branch: "develop",
                                 conclusion: "failure", created: t0, started: t0, updated: t0.addingTimeInterval(125))
        let rows = MenuModel.rows(state: state(.stale, running: [running], recent: [failed],
                                               failures: ["2#1": FailedStep(job: "build", step: "Run tests")],
                                               active: ["PhilRoli/rettstat"]))
        XCTAssertEqual(rows, [
            .message("⚠︎ stale"),
            .section("Running"),
            .run(RunRow(glyph: .running, title: "rettstat · Deploy develop", branch: "develop",
                        timing: .elapsed(since: t0), detail: nil, url: running.htmlURL)),
            .separator,
            .section("Recent"),
            .run(RunRow(glyph: .failure, title: "rettstat · Deploy develop", branch: "develop",
                        timing: .finished(at: t0.addingTimeInterval(125), duration: 125),
                        detail: "build › Run tests", url: failed.htmlURL)),
            .separator,
            .openActions(["PhilRoli/rettstat"])
        ])
    }

    func testGlyphsAndTimings() {
        let queued = MenuModel.row(Run.fixture(status: "queued", conclusion: nil, created: t0), detail: nil)
        XCTAssertEqual(queued.glyph, .queued)
        XCTAssertEqual(queued.timing, .queued)
        let cancelled = MenuModel.row(Run.fixture(conclusion: "cancelled", created: t0, updated: t0), detail: "x")
        XCTAssertEqual(cancelled.glyph, .cancelled)
        XCTAssertEqual(cancelled.timing, .cancelled(at: t0))
        XCTAssertNil(cancelled.detail) // details only for failures
        XCTAssertEqual(MenuModel.row(Run.fixture(conclusion: "skipped", created: t0), detail: nil).glyph, .skipped)
        XCTAssertEqual(MenuModel.row(Run.fixture(branch: nil, created: t0), detail: nil).branch, "")
    }

    func testTimingText() {
        let now = t0.addingTimeInterval(102)
        XCTAssertEqual(MenuModel.timingText(.queued, now: now), "queued")
        XCTAssertEqual(MenuModel.timingText(.elapsed(since: t0), now: now), "1:42")
        XCTAssertEqual(MenuModel.timingText(.finished(at: t0, duration: 82), now: t0.addingTimeInterval(180)),
                       "3m ago · 1m 22s")
        XCTAssertEqual(MenuModel.timingText(.cancelled(at: t0), now: t0.addingTimeInterval(7_200)),
                       "2h ago · cancelled")
    }

    func testActionsURL() {
        XCTAssertEqual(MenuModel.actionsURL("me/app").absoluteString, "https://github.com/me/app/actions")
    }
}
