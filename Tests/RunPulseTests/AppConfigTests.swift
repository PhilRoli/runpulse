import XCTest
@testable import RunPulse

final class AppConfigTests: XCTestCase {
    private var suite: TestDefaults!

    override func setUp() { suite = TestDefaults() }
    override func tearDown() { suite.tearDown() }

    func testDefaults() {
        let config = AppConfigStore(defaults: suite.defaults).load()
        XCTAssertEqual(config, AppConfig())
        XCTAssertEqual(config.lookbackDays, 7)
        XCTAssertEqual(config.muted, [])
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertEqual(AppConfig.lookbackChoices, [1, 3, 7, 14])
    }

    func testRoundTrip() {
        let store = AppConfigStore(defaults: suite.defaults)
        var config = AppConfig()
        config.lookbackDays = 3
        config.muted = ["me/old"]
        config.notificationsEnabled = false
        store.save(config)
        XCTAssertEqual(store.load(), config)
    }

    func testMissingKeysAndCorruptData() {
        suite.defaults.set(Data(#"{"lookbackDays":14}"#.utf8), forKey: "config")
        let config = AppConfigStore(defaults: suite.defaults).load()
        XCTAssertEqual(config.lookbackDays, 14)
        XCTAssertTrue(config.notificationsEnabled)
        suite.defaults.set(Data("nope".utf8), forKey: "config")
        XCTAssertEqual(AppConfigStore(defaults: suite.defaults).load(), AppConfig())
    }
}
