import XCTest
@testable import RunPulse

private final class FakeLoginItemManager: LoginItemManaging {
    var isEnabled = false
    var shouldFail = false

    func register() throws {
        if shouldFail { throw NSError(domain: "test", code: 1) }
        isEnabled = true
    }

    func unregister() throws {
        if shouldFail { throw NSError(domain: "test", code: 1) }
        isEnabled = false
    }
}

@MainActor
final class LoginItemTests: XCTestCase {
    func testToggle() {
        let controller = LoginItemController(manager: FakeLoginItemManager())
        XCTAssertTrue(controller.setEnabled(true))
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.setEnabled(false))
        XCTAssertFalse(controller.isEnabled)
    }

    func testFailureReportsFalse() {
        let manager = FakeLoginItemManager()
        manager.shouldFail = true
        XCTAssertFalse(LoginItemController(manager: manager).setEnabled(true))
    }
}
