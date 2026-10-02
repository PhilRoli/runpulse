import XCTest
@testable import RunPulse

final class PreferencesLogicTests: XCTestCase {
    func testTokenInput() {
        XCTAssertEqual(PreferencesLogic.tokenInput(""), .keep)
        XCTAssertEqual(PreferencesLogic.tokenInput(" \n"), .keep)
        XCTAssertEqual(PreferencesLogic.tokenInput(" ghp_x\n"), .set("ghp_x"))
    }

    func testAccountLabel() {
        var state = PollerState()
        XCTAssertEqual(PreferencesLogic.accountLabel(state), "Not signed in")
        state.account = "PhilRoli"
        state.tokenSource = .gh
        XCTAssertEqual(PreferencesLogic.accountLabel(state), "PhilRoli · gh CLI")
        state.tokenSource = .keychain
        XCTAssertEqual(PreferencesLogic.accountLabel(state), "PhilRoli · token")
    }

    func testRepoRowsKeepMutedReposVisible() {
        let rows = PreferencesLogic.repoRows(discovered: ["me/b", "org/secret"], muted: ["me/a"],
                                             noAccess: ["org/secret"])
        XCTAssertEqual(rows, [RepoRow(name: "me/a", enabled: false, noAccess: false),
                              RepoRow(name: "me/b", enabled: true, noAccess: false),
                              RepoRow(name: "org/secret", enabled: true, noAccess: true)])
    }

    func testMutedToggle() {
        XCTAssertEqual(PreferencesLogic.muted(["me/a"], repo: "me/b", enabled: false), ["me/a", "me/b"])
        XCTAssertEqual(PreferencesLogic.muted(["me/a", "me/b"], repo: "me/a", enabled: true), ["me/b"])
        XCTAssertEqual(PreferencesLogic.muted([], repo: "me/a", enabled: true), [])
    }
}
