import XCTest
@testable import RunPulse

final class ModelsTests: XCTestCase {
    func testDecodesRunsPage() throws {
        let page = try JSONCoding.decoder.decode(RunsPage.self, from: Data(JSONFixtures.runsPage.utf8))
        XCTAssertEqual(page.workflowRuns.count, 2)
        let release = page.workflowRuns[0]
        XCTAssertEqual(release.id, 37021588860)
        XCTAssertEqual(release.repo, "PhilRoli/claudeusage")
        XCTAssertEqual(release.repoName, "claudeusage")
        XCTAssertEqual(release.workflow, "Release")
        XCTAssertEqual(release.branch, "v1.0.1")
        XCTAssertEqual(release.state, .success)
        XCTAssertEqual(release.updatedAt, ISO8601DateFormatter().date(from: "2026-10-02T14:42:32Z"))
        XCTAssertEqual(release.key, "37021588860#1")
        let ci = page.workflowRuns[1]
        XCTAssertEqual(ci.state, .inProgress)
        XCTAssertNil(ci.startedAt)
        XCTAssertEqual(ci.attempt, 1) // run_attempt missing → 1
    }

    func testDecodesRepos() throws {
        let repos = try JSONCoding.decoder.decode([Repo].self, from: Data(JSONFixtures.repos.utf8))
        XCTAssertEqual(repos.map(\.fullName), ["PhilRoli/homebrew-tap", "KBastianK/CADS"])
        XCTAssertNotNil(repos[0].pushedAt)
        XCTAssertNil(repos[1].pushedAt)
        XCTAssertTrue(repos[1].archived)
    }

    func testRunStates() {
        let at = Date()
        func state(_ status: String, _ conclusion: String?) -> RunState {
            Run.fixture(status: status, conclusion: conclusion, created: at).state
        }
        XCTAssertEqual(state("queued", nil), .queued)
        XCTAssertEqual(state("waiting", nil), .queued)
        XCTAssertEqual(state("pending", nil), .queued)
        XCTAssertEqual(state("requested", nil), .queued)
        XCTAssertEqual(state("in_progress", nil), .inProgress)
        XCTAssertEqual(state("completed", "success"), .success)
        XCTAssertEqual(state("completed", "failure"), .failure)
        XCTAssertEqual(state("completed", "timed_out"), .failure)
        XCTAssertEqual(state("completed", "startup_failure"), .failure)
        XCTAssertEqual(state("completed", "cancelled"), .cancelled)
        XCTAssertEqual(state("completed", "skipped"), .skipped)
        XCTAssertEqual(state("completed", "neutral"), .skipped)
        XCTAssertEqual(state("completed", "action_required"), .other)
        XCTAssertFalse(RunState.queued.isCompleted)
        XCTAssertFalse(RunState.inProgress.isCompleted)
        XCTAssertTrue(RunState.other.isCompleted)
    }

    func testFailedStepLabel() {
        XCTAssertEqual(FailedStep(job: "build", step: "Run tests").label, "build › Run tests")
        XCTAssertEqual(FailedStep(job: "deploy", step: nil).label, "deploy")
    }
}
