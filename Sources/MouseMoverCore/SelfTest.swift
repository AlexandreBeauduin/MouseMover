import ApplicationServices
import Foundation

public struct SelfTestReport: Codable, Equatable {
    public var accessibilityTrusted: Bool
    public var displayID: UInt32
    public var bounds: [Int]
    public var visited: [[Int]]
    public var finalPosition: [Int]
    public var outcome: String
    public var cornersReached: Int
    public var passed: Bool
}

/// Driver that forwards to the real driver and records the actual cursor position after each action.
final class RecordingMouseDriver: MouseDriver {
    private let base: CGMouseDriver
    private(set) var positions: [Point] = []

    init(base: CGMouseDriver) {
        self.base = base
    }

    func position() -> Point { base.position() }

    func move(to point: Point, duration: Double, easing: Easing) throws {
        try base.move(to: point, duration: duration, easing: easing)
        positions.append(base.position())
    }

    func glide(to point: Point, duration: Double) throws {
        try base.glide(to: point, duration: duration)
        positions.append(base.position())
    }

    func click() throws { try base.click() }
    func sleep(_ seconds: Double) { base.sleep(seconds) }
}

/// Self-test: plays a real cycle on the main display and checks that the cursor really went
/// near the four corners and then back to the center.
public enum SelfTest {
    public static func run(displays: DisplayProviding = SystemDisplayProvider()) -> SelfTestReport {
        let trusted = AXIsProcessTrusted()
        guard let display = DisplayCatalog.resolve(selected: nil, in: displays.activeDisplays()) else {
            return SelfTestReport(
                accessibilityTrusted: trusted, displayID: 0, bounds: [], visited: [],
                finalPosition: [], outcome: "noDisplay", cornersReached: 0, passed: false)
        }

        let recorder = RecordingMouseDriver(base: CGMouseDriver())
        let outcome = ActivityCycle(driver: recorder, random: SystemRandom()).run(on: display)

        let bounds = display.bounds
        let targets = [
            Point(x: bounds.minX, y: bounds.maxY), Point(x: bounds.minX, y: bounds.minY),
            Point(x: bounds.maxX, y: bounds.minY), Point(x: bounds.maxX, y: bounds.maxY),
        ].map { ActivityCycle.clamp($0, to: bounds) }

        let tolerance = 6
        let cornersReached = targets.filter { target in
            recorder.positions.contains { abs($0.x - target.x) <= tolerance && abs($0.y - target.y) <= tolerance }
        }.count

        let final = recorder.position()
        let center = bounds.center
        let backAtCenter = abs(final.x - center.x) <= tolerance && abs(final.y - center.y) <= tolerance

        return SelfTestReport(
            accessibilityTrusted: trusted,
            displayID: display.id,
            bounds: [bounds.minX, bounds.maxX, bounds.minY, bounds.maxY],
            visited: recorder.positions.map { [$0.x, $0.y] },
            finalPosition: [final.x, final.y],
            outcome: String(describing: outcome),
            cornersReached: cornersReached,
            passed: outcome == .completed && cornersReached == 4 && backAtCenter)
    }
}
