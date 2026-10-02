import XCTest
@testable import RunPulse

final class FormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(Format.clock(0), "0:00")
        XCTAssertEqual(Format.clock(18), "0:18")
        XCTAssertEqual(Format.clock(102), "1:42")
        XCTAssertEqual(Format.clock(725), "12:05")
        XCTAssertEqual(Format.clock(3_723), "1:02:03")
        XCTAssertEqual(Format.clock(-5), "0:00")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(82), "1m 22s")
        XCTAssertEqual(Format.duration(3_900), "1h 5m")
        XCTAssertEqual(Format.duration(-1), "0s")
    }

    func testAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-12), now: now), "12s ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-180), now: now), "3m ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-7_200), now: now), "2h ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(-2 * 86_400), now: now), "2d ago")
        XCTAssertEqual(Format.age(since: now.addingTimeInterval(5), now: now), "0s ago")
    }

    func testTime() {
        let date = Date(timeIntervalSince1970: 1_790_958_745) // 2026-10-02 16:32:25 UTC
        XCTAssertEqual(Format.time(date, timeZone: TimeZone(identifier: "UTC")!), "16:32")
    }
}
