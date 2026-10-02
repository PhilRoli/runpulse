import UserNotifications
import XCTest
@testable import RunPulse

private final class FakeScheduler: NotificationScheduler, @unchecked Sendable {
    var requests: [UNNotificationRequest] = []
    var authRequests = 0

    func add(_ request: UNNotificationRequest,
             withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
        requests.append(request)
        completionHandler?(nil)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authRequests += 1
        return true
    }
}

@MainActor
final class NotificationManagerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ conclusion: String?, status: String = "completed", branch: String? = "v1.0.1") -> Run {
        Run.fixture(id: 9, repo: "PhilRoli/claudeusage", workflow: "Release", branch: branch, status: status,
                    conclusion: conclusion, created: t0, started: t0, updated: t0.addingTimeInterval(82))
    }

    func testSuccessMessage() {
        let message = NotificationManager.message(for: run("success"), detail: nil)
        let url = URL(string: "https://github.com/PhilRoli/claudeusage/actions/runs/9")!
        XCTAssertEqual(message, NotificationMessage(title: "✓ claudeusage · Release passed", body: "v1.0.1 · 1m 22s",
                                                    url: url))
    }

    func testFailureMessages() {
        let detail = FailedStep(job: "build", step: "Run tests")
        XCTAssertEqual(NotificationManager.message(for: run("failure", branch: "develop"), detail: detail)?.body,
                       "build › Run tests · develop")
        XCTAssertEqual(NotificationManager.message(for: run("timed_out", branch: "develop"), detail: nil)?.title,
                       "✗ claudeusage · Release failed")
        XCTAssertEqual(NotificationManager.message(for: run("failure", branch: "develop"), detail: nil)?.body,
                       "develop")
    }

    func testCancelledAndSilentStates() {
        XCTAssertEqual(NotificationManager.message(for: run("cancelled"), detail: nil)?.title,
                       "⊘ claudeusage · Release cancelled")
        XCTAssertNil(NotificationManager.message(for: run("skipped"), detail: nil))
        XCTAssertNil(NotificationManager.message(for: run(nil, status: "in_progress"), detail: nil))
    }

    func testPostSchedulesWithURL() {
        let scheduler = FakeScheduler()
        let manager = NotificationManager(scheduler: scheduler)
        manager.post([FinishedEvent(run: run("success")), FinishedEvent(run: run("skipped"))], details: [:])
        XCTAssertEqual(scheduler.requests.count, 1)
        XCTAssertEqual(scheduler.requests.first?.content.userInfo["url"] as? String,
                       "https://github.com/PhilRoli/claudeusage/actions/runs/9")
    }

    func testNothingToPostSkipsAuthorization() async {
        let scheduler = FakeScheduler()
        NotificationManager(scheduler: scheduler).post([FinishedEvent(run: run("skipped"))], details: [:])
        await Task.yield()
        XCTAssertEqual(scheduler.authRequests, 0)
    }

    func testRequestAuthorizationRunsOnce() async {
        let scheduler = FakeScheduler()
        let manager = NotificationManager(scheduler: scheduler)
        manager.requestAuthorization()
        manager.post([FinishedEvent(run: run("success"))], details: [:])
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(scheduler.authRequests, 1)
    }

    func testRequestIdentifierIsRunKey() {
        let scheduler = FakeScheduler()
        NotificationManager(scheduler: scheduler).post([FinishedEvent(run: run("success"))], details: [:])
        XCTAssertEqual(scheduler.requests.first?.identifier, "9#1")
    }

    func testOnlyWebURLsAreOpenable() {
        XCTAssertNotNil(NotificationPresenter.openableURL("https://github.com/a/b"))
        XCTAssertNotNil(NotificationPresenter.openableURL("http://github.com/a/b"))
        XCTAssertNil(NotificationPresenter.openableURL("file:///etc/passwd"))
        XCTAssertNil(NotificationPresenter.openableURL("x-apple.systempreferences:foo"))
        XCTAssertNil(NotificationPresenter.openableURL("not a url"))
    }
}
