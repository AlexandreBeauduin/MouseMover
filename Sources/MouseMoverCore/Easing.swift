import Foundation

/// Courbes d'acceleration identiques a celles de pytweening utilisees par la version Python.
public enum Easing: CaseIterable, Sendable {
    case easeInOutQuad
    case easeOutQuad
    case easeInOutSine

    public func apply(_ t: Double) -> Double {
        switch self {
        case .easeInOutQuad:
            if t < 0.5 { return 2 * t * t }
            let n = t * 2 - 1
            return -0.5 * (n * (n - 2) - 1)
        case .easeOutQuad:
            return -t * (t - 2)
        case .easeInOutSine:
            return -0.5 * (cos(Double.pi * t) - 1)
        }
    }
}
