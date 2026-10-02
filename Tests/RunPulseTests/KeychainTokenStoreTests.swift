import XCTest
@testable import RunPulse

/// Real login Keychain, unique service per test, item deleted in tearDown.
final class KeychainTokenStoreTests: XCTestCase {
    private var store: KeychainTokenStore!

    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "no interactive Keychain on CI")
        store = KeychainTokenStore(service: "RunPulseTests-\(UUID().uuidString)", account: "pat")
    }

    override func tearDown() {
        try? store?.delete()
    }

    func testRoundTripTrimAndDelete() throws {
        XCTAssertNil(try store.read())
        try store.save("  ghp_abc\"q\\x \n")
        XCTAssertEqual(try store.read(), "ghp_abc\"q\\x")
        try store.save("second")
        XCTAssertEqual(try store.read(), "second")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testRejectsEmptyAndMultiline() {
        XCTAssertThrowsError(try store.save(" \n"))
        XCTAssertThrowsError(try store.save("a\nb"))
    }
}

final class KeychainQuoteTests: XCTestCase {
    func testQuote() {
        XCTAssertEqual(KeychainTokenStore.quote(#"a"b\c"#), #""a\"b\\c""#)
    }
}
