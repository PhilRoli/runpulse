import XCTest
@testable import RunPulse

final class StatusTitleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func title(_ status: PollStatus = .ok, running: Int = 0, successAgo: TimeInterval? = nil,
                       failure: Bool = false) -> StatusTitle {
        StatusTitle.make(TitleInput(status: status, runningCount: running,
                                    lastSuccessAt: successAgo.map { now.addingTimeInterval(-$0) },
                                    failureUnacknowledged: failure), now: now)
    }

    func testIdle() {
        XCTAssertEqual(title(), StatusTitle(text: "", tint: .normal))
    }

    func testAuthProblemsShowBang() {
        XCTAssertEqual(title(.authMissing), StatusTitle(text: "!", tint: .orange))
        XCTAssertEqual(title(.authFailed, running: 2), StatusTitle(text: "!", tint: .orange))
    }

    func testRunningCount() {
        XCTAssertEqual(title(running: 2, failure: true), StatusTitle(text: "2", tint: .normal))
    }

    func testFailureBeatsLaterSuccess() {
        XCTAssertEqual(title(successAgo: 10, failure: true), StatusTitle(text: "✗", tint: .red))
    }

    func testSuccessFadesAfterFiveMinutes() {
        XCTAssertEqual(title(successAgo: 299), StatusTitle(text: "✓", tint: .green))
        XCTAssertEqual(title(successAgo: 300), StatusTitle(text: "", tint: .normal))
    }

    func testStaleAppendsStar() {
        XCTAssertEqual(title(.stale, running: 1).text, "1*")
        XCTAssertEqual(title(.stale).text, "*")
    }
}
