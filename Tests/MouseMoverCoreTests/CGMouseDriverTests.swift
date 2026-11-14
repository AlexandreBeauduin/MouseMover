import XCTest
@testable import MouseMoverCore

final class CGMouseDriverTests: XCTestCase {
    func testFailSafeCheckOnlyTriggersAtOrigin() {
        // Does not move the mouse: only checks the position logic.
        let driver = CGMouseDriver()
        let origin = driver.position() == Point(x: 0, y: 0)
        if origin {
            XCTAssertThrowsError(try driver.failSafeCheck())
        } else {
            XCTAssertNoThrow(try driver.failSafeCheck())
        }
    }

    func testSelfTestReportRoundTripsAsJSON() throws {
        let report = SelfTestReport(
            accessibilityTrusted: true, displayID: 1, bounds: [0, 10, 0, 10], visited: [[1, 2]],
            finalPosition: [5, 5], outcome: "completed", cornersReached: 4, passed: true)
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(SelfTestReport.self, from: data), report)
    }
}
