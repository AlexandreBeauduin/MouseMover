import XCTest
@testable import MouseMoverCore

final class GestureRecorderTests: XCTestCase {
    private let bounds = DisplayBounds(minX: 0, maxX: 1000, minY: 0, maxY: 1000)

    /// Samples at 60 Hz along a segment.
    private func line(from a: Point, to b: Point, start: Double, duration: Double) -> [GestureSample] {
        let steps = max(1, Int(duration * 60))
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            return GestureSample(
                time: start + t * duration,
                point: Point(x: a.x + Int((Double(b.x - a.x) * t).rounded()),
                             y: a.y + Int((Double(b.y - a.y) * t).rounded())))
        }
    }

    private func still(at p: Point, from start: Double, duration: Double) -> [GestureSample] {
        stride(from: start, through: start + duration, by: 1.0 / 60).map { GestureSample(time: $0, point: p) }
    }

    func testNoSamplesGivesNoPattern() {
        XCTAssertNil(GestureRecorder.pattern(from: [], in: bounds))
    }

    func testStraightLineCollapsesToTwoPoints() throws {
        let samples = line(from: Point(x: 100, y: 100), to: Point(x: 900, y: 500), start: 0, duration: 1)
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: bounds))
        XCTAssertEqual(pattern.points.count, 2)
        XCTAssertEqual(pattern.points[0].x, 0.1)
        XCTAssertEqual(pattern.points[0].y, 0.1)
        XCTAssertNil(pattern.points[0].duration)
        XCTAssertEqual(pattern.points[1].x, 0.9)
        XCTAssertEqual(pattern.points[1].y, 0.5)
        XCTAssertEqual(try XCTUnwrap(pattern.points[1].duration), 1, accuracy: 0.02)
        XCTAssertEqual(pattern.anchor, .screen)
        XCTAssertFalse(pattern.shuffle)
    }

    func testCornerIsKept() throws {
        let samples = line(from: Point(x: 100, y: 100), to: Point(x: 900, y: 100), start: 0, duration: 0.5)
            + line(from: Point(x: 900, y: 100), to: Point(x: 900, y: 900), start: 0.5, duration: 0.5)
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: bounds))
        XCTAssertEqual(pattern.points.map(\.x), [0.1, 0.9, 0.9])
        XCTAssertEqual(pattern.points.map(\.y), [0.1, 0.1, 0.9])
    }

    func testStopsBecomePausesButLeadingAndTrailingWaitsAreDropped() throws {
        let a = Point(x: 200, y: 200), b = Point(x: 600, y: 200), c = Point(x: 600, y: 600)
        let samples = still(at: a, from: 0, duration: 1)
            + line(from: a, to: b, start: 1, duration: 0.5)
            + still(at: b, from: 1.5, duration: 0.6)
            + line(from: b, to: c, start: 2.1, duration: 0.5)
            + still(at: c, from: 2.6, duration: 2)
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: bounds))
        XCTAssertEqual(pattern.points.count, 3)
        XCTAssertNil(pattern.points[0].pause)
        XCTAssertEqual(try XCTUnwrap(pattern.points[1].pause?.min), 0.6, accuracy: 0.05)
        XCTAssertNil(pattern.points[2].pause)
        XCTAssertEqual(try XCTUnwrap(pattern.points[1].duration), 0.5, accuracy: 0.05)
    }

    func testClicksAreKeptAtTheirPosition() throws {
        var samples = line(from: Point(x: 100, y: 100), to: Point(x: 900, y: 100), start: 0, duration: 1)
        samples[30].click = true
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: bounds))
        let clicked = pattern.points.filter(\.click)
        XCTAssertEqual(clicked.count, 1)
        XCTAssertEqual(clicked[0].x, 0.5, accuracy: 0.01)
    }

    func testDoubleClickInPlaceGivesTwoClicks() throws {
        let p = Point(x: 500, y: 500)
        let samples = [GestureSample(time: 0, point: p, click: true), GestureSample(time: 0.1, point: p, click: true)]
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: bounds))
        XCTAssertEqual(pattern.points.filter(\.click).count, 2)
    }

    func testCoordinatesAreRelativeToDisplayOrigin() throws {
        let left = Fixtures.left.bounds
        let samples = line(from: Point(x: -2560 + 256, y: 144), to: Point(x: -256, y: 1296), start: 0, duration: 0.3)
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: left))
        XCTAssertEqual(pattern.points.first?.x ?? -1, 0.1, accuracy: 0.001)
        XCTAssertEqual(pattern.points.last?.y ?? -1, 0.9, accuracy: 0.001)
    }

    func testLongWigglyGestureIsCappedAndReplayable() throws {
        let samples = (0..<3000).map { i in
            GestureSample(time: Double(i) / 60,
                          point: Point(x: 500 + Int(400 * sin(Double(i) / 3)), y: 500 + Int(400 * cos(Double(i) / 7))))
        }
        let pattern = try XCTUnwrap(GestureRecorder.pattern(from: samples, in: bounds))
        XCTAssertLessThanOrEqual(pattern.points.count, MousePattern.maxPoints)
        XCTAssertEqual(pattern, pattern.sanitized())
        let driver = FakeMouseDriver()
        XCTAssertEqual(ActivityCycle(driver: driver, random: FakeRandom()).run(pattern, on: Fixtures.main), .completed)
    }
}
