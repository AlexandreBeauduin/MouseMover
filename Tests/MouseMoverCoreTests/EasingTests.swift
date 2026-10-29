import XCTest
@testable import MouseMoverCore

final class EasingTests: XCTestCase {
    func testEndpoints() {
        for easing in Easing.allCases {
            XCTAssertEqual(easing.apply(0), 0, accuracy: 1e-12, "\(easing)")
            XCTAssertEqual(easing.apply(1), 1, accuracy: 1e-12, "\(easing)")
        }
    }

    func testMidpoints() {
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Easing.easeInOutSine.apply(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Easing.easeOutQuad.apply(0.5), 0.75, accuracy: 1e-12)
    }

    func testKnownValuesMatchPytweening() {
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.25), 0.125, accuracy: 1e-12)
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.75), 0.875, accuracy: 1e-12)
        XCTAssertEqual(Easing.easeOutQuad.apply(0.25), 0.4375, accuracy: 1e-12)
        XCTAssertEqual(Easing.easeInOutSine.apply(0.25), 0.1464466094, accuracy: 1e-9)
    }

    func testMonotonic() {
        for easing in Easing.allCases {
            var previous = -1.0
            for i in 0...100 {
                let value = easing.apply(Double(i) / 100)
                XCTAssertGreaterThanOrEqual(value, previous, "\(easing) @ \(i)")
                previous = value
            }
        }
    }
}
