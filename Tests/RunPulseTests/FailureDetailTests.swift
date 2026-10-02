import XCTest
@testable import RunPulse

final class FailureDetailTests: XCTestCase {
    func testFirstFailedJobAndStep() {
        XCTAssertEqual(FailureDetail.parse(Data(JSONFixtures.jobsFailed.utf8)),
                       FailedStep(job: "build", step: "Run tests"))
    }

    func testTimedOutJobWithoutSteps() {
        XCTAssertEqual(FailureDetail.parse(Data(JSONFixtures.jobsTimedOutNoSteps.utf8)),
                       FailedStep(job: "deploy", step: nil))
    }

    func testNoFailureOrGarbage() {
        XCTAssertNil(FailureDetail.parse(Data(JSONFixtures.jobsOK.utf8)))
        XCTAssertNil(FailureDetail.parse(Data("<html>".utf8)))
    }
}
