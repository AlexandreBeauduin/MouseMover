import Foundation

/// Un cycle d'activite souris sur un ecran : joue un motif, par defaut le motif « Classique »
/// (centre, clic, quatre coins dans un ordre aleatoire, retour au centre).
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

    /// Position reelle d'un point du motif. Ecran : (0, 0) est le coin haut gauche, (1, 1) le coin bas droit.
    /// Curseur : (0.5, 0.5) est la position du curseur, l'echelle reste celle de l'ecran.
    public static func locate(_ point: PatternPoint, in bounds: DisplayBounds, origin: Point?) -> Point {
        let width = Double(bounds.maxX - bounds.minX)
        let height = Double(bounds.maxY - bounds.minY)
        guard let origin else {
            return Point(x: bounds.minX + Int((point.x * width).rounded(.down)),
                         y: bounds.minY + Int((point.y * height).rounded(.down)))
        }
        return Point(x: origin.x + Int(((point.x - 0.5) * width).rounded(.down)),
                     y: origin.y + Int(((point.y - 0.5) * height).rounded(.down)))
    }

    public func run(on display: DisplayInfo) -> Outcome {
        run(.classic, on: display)
    }

    /// Ne leve jamais d'erreur : le failsafe ou toute autre erreur interrompt simplement le cycle.
    /// `displays` sert au repere « curseur » : on reste sur l'ecran ou se trouve le curseur.
    public func run(_ pattern: MousePattern, on display: DisplayInfo, displays: [DisplayInfo] = []) -> Outcome {
        var bounds = display.bounds
        var origin: Point?
        if pattern.anchor == .cursor {
            let cursor = driver.position()
            if let current = (displays + [display]).first(where: { $0.bounds.contains(cursor) }) {
                bounds = current.bounds
                origin = cursor
            } else {
                origin = bounds.center
            }
        }

        // Melange au premier point mobile (et non avant) : meme suite de tirages que la version Python.
        var order: [PatternPoint]? = pattern.shuffle ? nil : pattern.points
        do {
            for index in pattern.points.indices {
                if order == nil, !pattern.points[index].fixed {
                    order = pattern.order(shuffledBy: random)
                }
                let point = order?[index] ?? pattern.points[index]
                let target = Self.clamp(Self.locate(point, in: bounds, origin: origin), to: bounds)
                try humanMove(to: target, duration: point.duration)
                if let pause = point.pause { humanPause(pause.min, pause.max) }
                if point.click { try driver.click() }
            }
            return .completed
        } catch MouseError.failSafeTriggered {
            Log.core.notice("Failsafe declenche (souris dans un coin), cycle ignore.")
            return .failSafe
        } catch {
            Log.core.error("Erreur pendant le cycle d'activite (ignoree): \(String(describing: error))")
            return .failed
        }
    }

    /// Sans duree imposee : leger decalage, duree et courbe aleatoires. Avec une duree : trajet exact et lineaire.
    func humanMove(to target: Point, duration: Double? = nil) throws {
        if let duration {
            try driver.glide(to: target, duration: duration)
            return
        }
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
