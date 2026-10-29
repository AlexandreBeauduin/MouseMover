import XCTest
@testable import MouseMoverCore

final class ActivityCycleTests: XCTestCase {
    private func makeCycle() -> (ActivityCycle, FakeMouseDriver, FakeRandom) {
        let driver = FakeMouseDriver()
        let random = FakeRandom()
        return (ActivityCycle(driver: driver, random: random), driver, random)
    }

    func testClampKeepsSafeMargin() {
        let bounds = Fixtures.main.bounds
        XCTAssertEqual(ActivityCycle.clamp(Point(x: 0, y: 1799), to: bounds), Point(x: 80, y: 1719))
        XCTAssertEqual(ActivityCycle.clamp(Point(x: 3199, y: 0), to: bounds), Point(x: 3119, y: 80))
        XCTAssertEqual(ActivityCycle.clamp(Point(x: 1599, y: 899), to: bounds), Point(x: 1599, y: 899))
    }

    func testClampWithNegativeOrigin() {
        let bounds = Fixtures.left.bounds
        XCTAssertEqual(ActivityCycle.clamp(Point(x: -2560, y: 0), to: bounds), Point(x: -2480, y: 80))
        XCTAssertEqual(ActivityCycle.clamp(Point(x: -1, y: 1439), to: bounds), Point(x: -81, y: 1359))
    }

    func testClampOnTinyDisplayDoesNotCrash() {
        let bounds = DisplayInfo(id: 9, x: 0, y: 0, width: 100, height: 100, isMain: true).bounds
        let point = ActivityCycle.clamp(Point(x: 50, y: 50), to: bounds)
        XCTAssertEqual(point, Point(x: 80, y: 80))
    }

    func testCompletedCycleVisitsCenterThenFourCornersThenCenter() {
        let (cycle, driver, _) = makeCycle()
        XCTAssertEqual(cycle.run(on: Fixtures.main), .completed)

        // Jitter minimal (1) => decalage de -1 sur chaque axe.
        let jitter = Point(x: -1, y: -1)
        func p(_ x: Int, _ y: Int) -> Point { Point(x: x + jitter.x, y: y + jitter.y) }
        XCTAssertEqual(driver.moves, [
            p(1599, 899),          // centre
            p(80, 1719),           // coin bas gauche (ordre non melange)
            p(80, 80),
            p(3119, 80),
            p(3119, 1719),
            p(1599, 899),          // retour au centre
        ])
        XCTAssertEqual(driver.clickCount, 1)
    }

    func testClickHappensAfterFirstMoveAndBeforeCorners() {
        let (cycle, driver, _) = makeCycle()
        _ = cycle.run(on: Fixtures.main)
        let firstMove = driver.events.firstIndex { if case .move = $0 { return true } else { return false } }
        let click = driver.events.firstIndex(of: .click)
        XCTAssertEqual(firstMove, 0)
        XCTAssertEqual(click, 2) // move, pause 0.08-0.18, click
        XCTAssertEqual(driver.events[1], .sleep(0.08))
    }

    func testRandomCallOrderMatchesPython() {
        let (cycle, _, random) = makeCycle()
        _ = cycle.run(on: Fixtures.main)

        let humanMove = ["int 1...4", "int -1...1", "int -1...1", "double 0.18...0.35", "choice 3"]
        XCTAssertEqual(Array(random.calls.prefix(5)), humanMove)
        XCTAssertEqual(random.calls[5], "double 0.08...0.18")
        XCTAssertEqual(random.calls[6], "shuffled 4")
        XCTAssertEqual(Array(random.calls[7..<12]), humanMove)
        XCTAssertEqual(random.calls[12], "double 0.05...0.25")
    }

    func testShuffledOrderIsUsed() {
        let (cycle, driver, random) = makeCycle()
        random.reversed = true
        _ = cycle.run(on: Fixtures.main)
        XCTAssertEqual(driver.moves[1], Point(x: 3119 - 1, y: 1719 - 1))
        XCTAssertEqual(driver.moves[4], Point(x: 80 - 1, y: 1719 - 1))
    }

    func testMoveDurationAndEasingComeFromRandom() {
        let (cycle, driver, random) = makeCycle()
        random.doubleValue = 0.3
        _ = cycle.run(on: Fixtures.main)
        guard case .move(_, let duration, let easing) = driver.events[0] else { return XCTFail() }
        XCTAssertEqual(duration, 0.3)
        XCTAssertEqual(easing, .easeInOutQuad)
    }

    func testFailSafeOnFirstMoveStopsCycleWithoutThrowing() {
        let (cycle, driver, _) = makeCycle()
        driver.failOnAction = 1
        XCTAssertEqual(cycle.run(on: Fixtures.main), .failSafe)
        XCTAssertEqual(driver.clickCount, 0)
        XCTAssertTrue(driver.moves.isEmpty)
    }

    func testFailSafeMidCycleStopsRemainingMoves() {
        let (cycle, driver, _) = makeCycle()
        driver.failOnAction = 4 // move, click, move, [move X]
        XCTAssertEqual(cycle.run(on: Fixtures.main), .failSafe)
        XCTAssertEqual(driver.moves.count, 2)
    }

    func testFailSafeOnClickIsHandled() {
        let (cycle, driver, _) = makeCycle()
        driver.failOnAction = 2
        XCTAssertEqual(cycle.run(on: Fixtures.main), .failSafe)
        XCTAssertEqual(driver.moves.count, 1)
    }

    func testOtherErrorsAreAlsoSwallowed() {
        let (cycle, driver, _) = makeCycle()
        driver.error = MouseError.eventCreationFailed
        driver.failOnAction = 3
        XCTAssertEqual(cycle.run(on: Fixtures.main), .failed)
    }

    func testCycleOnNegativeOriginDisplayStaysInsideIt() {
        for display in [Fixtures.left, Fixtures.upperLeft] {
            let (cycle, driver, random) = makeCycle()
            random.intValue = 4 // jitter maximal
            XCTAssertEqual(cycle.run(on: display), .completed)
            let b = display.bounds
            for point in driver.moves {
                XCTAssertTrue((b.minX...b.maxX).contains(point.x), "\(point) hors de \(display)")
                XCTAssertTrue((b.minY...b.maxY).contains(point.y), "\(point) hors de \(display)")
            }
        }
    }

    func testCycleWithSystemRandomAlwaysCompletesAndStaysInside() {
        for _ in 0..<50 {
            let driver = FakeMouseDriver()
            let cycle = ActivityCycle(driver: driver, random: SystemRandom())
            XCTAssertEqual(cycle.run(on: Fixtures.upperLeft), .completed)
            let b = Fixtures.upperLeft.bounds
            XCTAssertTrue(driver.moves.allSatisfy {
                (b.minX...b.maxX).contains($0.x) && (b.minY...b.maxY).contains($0.y)
            })
            XCTAssertEqual(driver.moves.count, 6)
        }
    }
}
