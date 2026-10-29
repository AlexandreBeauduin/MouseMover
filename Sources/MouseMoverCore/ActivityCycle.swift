import Foundation

/// Un cycle d'activite souris sur un ecran : centre, clic, quatre coins dans un ordre aleatoire, retour au centre.
public struct ActivityCycle {
    public static let safeMargin = 80

    public enum Outcome: Equatable {
        case completed
        case failSafe
        case failed
    }

    public let driver: MouseDriver
    public let random: RandomSource

    public init(driver: MouseDriver, random: RandomSource) {
        self.driver = driver
        self.random = random
    }

    public static func clamp(_ point: Point, to bounds: DisplayBounds) -> Point {
        Point(
            x: max(bounds.minX + safeMargin, min(point.x, bounds.maxX - safeMargin)),
            y: max(bounds.minY + safeMargin, min(point.y, bounds.maxY - safeMargin)))
    }

    /// Ne leve jamais d'erreur : le failsafe ou toute autre erreur interrompt simplement le cycle.
    public func run(on display: DisplayInfo) -> Outcome {
        let bounds = display.bounds
        let safe = bounds.center
        let corners = [
            Point(x: bounds.minX, y: bounds.maxY),
            Point(x: bounds.minX, y: bounds.minY),
            Point(x: bounds.maxX, y: bounds.minY),
            Point(x: bounds.maxX, y: bounds.maxY),
        ]

        do {
            try humanMove(to: Self.clamp(safe, to: bounds))
            humanPause(0.08, 0.18)
            try driver.click()

            for corner in random.shuffled(corners) {
                try humanMove(to: Self.clamp(corner, to: bounds))
                humanPause()
            }

            try humanMove(to: safe)
            return .completed
        } catch MouseError.failSafeTriggered {
            Log.core.notice("Failsafe declenche (souris dans un coin), cycle ignore.")
            return .failSafe
        } catch {
            Log.core.error("Erreur pendant le cycle d'activite (ignoree): \(String(describing: error))")
            return .failed
        }
    }

    func humanMove(to target: Point) throws {
        let jitter = random.int(in: 1...4)
        let x = target.x + random.int(in: -jitter...jitter)
        let y = target.y + random.int(in: -jitter...jitter)
        let duration = random.double(in: 0.18...0.35)
        let easing = random.choice(Easing.allCases)
        try driver.move(to: Point(x: x, y: y), duration: duration, easing: easing)
    }

    func humanPause(_ lower: Double = 0.05, _ upper: Double = 0.25) {
        driver.sleep(random.double(in: lower...upper))
    }
}
