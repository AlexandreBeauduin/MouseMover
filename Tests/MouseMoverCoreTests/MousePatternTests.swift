import XCTest
@testable import MouseMoverCore

final class MousePatternTests: XCTestCase {
    private func decode(_ json: String) throws -> MousePattern {
        try JSONDecoder().decode(MousePattern.self, from: Data(json.utf8))
    }

    // MARK: Decodage tolerant

    func testRoundTripKeepsEverything() throws {
        let pattern = MousePattern(
            id: "abc", name: "Test", anchor: .cursor, shuffle: true,
            points: [
                PatternPoint(x: 0.1, y: 0.2, click: true, pause: PauseRange(min: 0.1, max: 0.3),
                             duration: 0.5, fixed: true),
                PatternPoint(x: 0.9, y: 0.8),
            ])
        let data = try JSONEncoder().encode(pattern)
        XCTAssertEqual(try JSONDecoder().decode(MousePattern.self, from: data), pattern)
    }

    func testEncodingOmitsDefaults() throws {
        let data = try JSONEncoder().encode(PatternPoint(x: 0.5, y: 0.25))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["x", "y"])
    }

    func testMissingFieldsGetDefaults() throws {
        let pattern = try decode(#"{"id": "a", "points": [{"x": 0.5, "y": 0.5}]}"#)
        XCTAssertEqual(pattern.name, "Motif")
        XCTAssertEqual(pattern.anchor, .screen)
        XCTAssertFalse(pattern.shuffle)
        XCTAssertEqual(pattern.points, [PatternPoint(x: 0.5, y: 0.5)])
    }

    func testInvalidPointsAreSkippedNotFatal() throws {
        let pattern = try decode(#"{"id": "a", "name": "x", "anchor": "moon", "points": [{"x": "a"}, {"x": 0.2, "y": 0.3}]}"#)
        XCTAssertEqual(pattern.anchor, .screen)
        XCTAssertEqual(pattern.points, [PatternPoint(x: 0.2, y: 0.3)])
    }

    func testValuesAreClampedIntoSafeRanges() throws {
        let pattern = try decode(#"""
        {"id": "a", "name": "  ", "points": [
          {"x": -1, "y": 7, "duration": 99, "pause_min": 9, "pause_max": -2},
          {"x": 0.5, "y": 0.5, "duration": 0.0001, "pause_max": 0.4}
        ]}
        """#)
        XCTAssertEqual(pattern.name, "Motif sans nom")
        XCTAssertEqual(pattern.points[0].x, 0)
        XCTAssertEqual(pattern.points[0].y, 1)
        XCTAssertEqual(pattern.points[0].duration, MousePattern.durationRange.upperBound)
        XCTAssertEqual(pattern.points[0].pause, PauseRange(min: 0, max: MousePattern.maxPause))
        XCTAssertEqual(pattern.points[1].duration, MousePattern.durationRange.lowerBound)
        XCTAssertEqual(pattern.points[1].pause, PauseRange(min: 0.4, max: 0.4))
    }

    func testPointCountIsCapped() {
        let points = Array(repeating: PatternPoint(x: 0.5, y: 0.5), count: MousePattern.maxPoints + 50)
        XCTAssertEqual(MousePattern(name: "x", points: points).sanitized().points.count, MousePattern.maxPoints)
    }

    func testNonFiniteValuesAreDropped() {
        let pattern = MousePattern(name: "x", points: [
            PatternPoint(x: .nan, y: 0.5),
            PatternPoint(x: 0.5, y: 0.5, duration: .infinity),
        ]).sanitized()
        XCTAssertEqual(pattern.points, [PatternPoint(x: 0.5, y: 0.5)])
    }

    // MARK: Motifs integres

    func testBuiltInsAreValidAndMarked() {
        XCTAssertEqual(Set(MousePattern.builtIns.map(\.id)).count, MousePattern.builtIns.count)
        for pattern in MousePattern.builtIns {
            XCTAssertTrue(pattern.isBuiltIn)
            XCTAssertFalse(pattern.points.isEmpty)
            XCTAssertEqual(pattern.sanitized(), pattern, pattern.name)
        }
        XCTAssertFalse(MousePattern(name: "x", points: []).isBuiltIn)
    }

    // MARK: Ordre

    func testFixedPointsKeepTheirSlotWhenShuffled() {
        let random = FakeRandom()
        random.reversed = true
        let order = MousePattern.classic.order(shuffledBy: random)
        XCTAssertEqual(random.calls, ["shuffled 4"])
        XCTAssertEqual(order.first, MousePattern.classic.points.first)
        XCTAssertEqual(order.last, MousePattern.classic.points.last)
        XCTAssertEqual(Array(order[1...4]), Array(MousePattern.classic.points[1...4].reversed()))
    }

    func testNoShuffleKeepsOrderWithoutRandom() {
        let random = FakeRandom()
        XCTAssertEqual(MousePattern.zigzag.order(shuffledBy: random), MousePattern.zigzag.points)
        XCTAssertTrue(random.calls.isEmpty)
    }
}

final class PatternPlaybackTests: XCTestCase {
    private let display = Fixtures.main

    func testScreenPointsAreFractionsOfTheDisplay() {
        let bounds = Fixtures.left.bounds
        XCTAssertEqual(ActivityCycle.locate(PatternPoint(x: 0.25, y: 0.5), in: bounds, origin: nil),
                       Point(x: -1921, y: 719)) // bornes inclusives : 2559 x 1439
    }

    func testCursorPointsAreRelativeToCursor() {
        let bounds = display.bounds
        let origin = Point(x: 1000, y: 900)
        XCTAssertEqual(ActivityCycle.locate(PatternPoint(x: 0.5, y: 0.5), in: bounds, origin: origin), origin)
        XCTAssertEqual(ActivityCycle.locate(PatternPoint(x: 0.6, y: 0.4), in: bounds, origin: origin),
                       Point(x: 1319, y: 720))
    }

    func testExplicitDurationGlidesWithoutRandomness() {
        let driver = FakeMouseDriver()
        let random = FakeRandom()
        let pattern = MousePattern(name: "x", points: [
            PatternPoint(x: 0.5, y: 0.5, duration: 0.4),
            PatternPoint(x: 0.25, y: 0.25, click: true, duration: 0.2),
        ])
        XCTAssertEqual(ActivityCycle(driver: driver, random: random).run(pattern, on: display), .completed)
        XCTAssertEqual(driver.events, [.glide(display.bounds.center, 0.4), .glide(Point(x: 799, y: 449), 0.2), .click])
        XCTAssertTrue(random.calls.isEmpty)
    }

    func testPauseHappensBeforeClick() {
        let driver = FakeMouseDriver()
        let pattern = MousePattern(name: "x", points: [
            PatternPoint(x: 0.5, y: 0.5, click: true, pause: PauseRange(min: 0.3, max: 0.6), duration: 0.1),
        ])
        _ = ActivityCycle(driver: driver, random: FakeRandom()).run(pattern, on: display)
        XCTAssertEqual(driver.events, [.glide(display.bounds.center, 0.1), .sleep(0.3), .click])
    }

    func testPointsAreClampedToSafeMargin() {
        let driver = FakeMouseDriver()
        let pattern = MousePattern(name: "x", points: [PatternPoint(x: 0, y: 0, duration: 0.1)])
        _ = ActivityCycle(driver: driver, random: FakeRandom()).run(pattern, on: display)
        XCTAssertEqual(driver.moves, [Point(x: ActivityCycle.safeMargin, y: ActivityCycle.safeMargin)])
    }

    func testCursorAnchorFollowsTheDisplayUnderTheCursor() {
        let driver = FakeMouseDriver()
        driver.current = Point(x: -1000, y: 500)
        _ = ActivityCycle(driver: driver, random: FakeRandom())
            .run(.discreet, on: display, displays: [Fixtures.left, display])
        XCTAssertEqual(driver.moves.last, Point(x: -1000, y: 500))
        for move in driver.moves {
            XCTAssertTrue(Fixtures.left.bounds.contains(move))
            XCTAssertLessThan(abs(move.x + 1000) + abs(move.y - 500), 20)
        }
    }

    func testCursorOutsideEveryDisplayFallsBackToCenter() {
        let driver = FakeMouseDriver()
        driver.current = Point(x: 99_999, y: 99_999)
        _ = ActivityCycle(driver: driver, random: FakeRandom()).run(.discreet, on: display, displays: [display])
        XCTAssertEqual(driver.moves.last, display.bounds.center)
    }

    func testEmptyPatternCompletesWithoutMoving() {
        let driver = FakeMouseDriver()
        XCTAssertEqual(ActivityCycle(driver: driver, random: FakeRandom())
            .run(MousePattern(name: "x", points: []), on: display), .completed)
        XCTAssertTrue(driver.events.isEmpty)
    }

    func testFailSafeDuringGlideStopsPattern() {
        let driver = FakeMouseDriver()
        driver.failOnAction = 2
        XCTAssertEqual(ActivityCycle(driver: driver, random: FakeRandom()).run(.circle, on: display), .failSafe)
        XCTAssertEqual(driver.moves.count, 1)
    }

    func testEveryBuiltInStaysInsideEveryDisplay() {
        for pattern in MousePattern.builtIns {
            for screen in [Fixtures.main, Fixtures.left, Fixtures.upperLeft] {
                let driver = FakeMouseDriver()
                driver.current = screen.bounds.center
                let outcome = ActivityCycle(driver: driver, random: SystemRandom())
                    .run(pattern, on: screen, displays: [screen])
                XCTAssertEqual(outcome, .completed)
                for move in driver.moves {
                    XCTAssertTrue(screen.bounds.contains(move), "\(pattern.name) \(move)")
                }
            }
        }
    }
}
