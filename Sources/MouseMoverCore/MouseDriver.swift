import ApplicationServices
import CoreGraphics
import Foundation

public enum MouseError: Error, Equatable {
    case failSafeTriggered
    case eventCreationFailed
}

public protocol MouseDriver: AnyObject {
    func position() -> Point
    func move(to point: Point, duration: Double, easing: Easing) throws
    /// Linear move at constant speed, no pause on arrival: used to replay a gesture.
    func glide(to point: Point, duration: Double) throws
    func click() throws
    func sleep(_ seconds: Double)
}

/// Real driver based on CGEvent. Mimics pyautogui: fail-safe at (0, 0), a pause after each
/// action, interpolated moves with an easing curve.
public final class CGMouseDriver: MouseDriver {
    public static let minimumDuration = 0.1

    public var callPause: Double
    public var stepsPerSecond: Double

    public init(callPause: Double = 0.1, stepsPerSecond: Double = 120) {
        self.callPause = callPause
        self.stepsPerSecond = stepsPerSecond
    }

    public func position() -> Point {
        let location = CGEvent(source: nil)?.location ?? .zero
        return Point(x: Int(location.x), y: Int(location.y))
    }

    public func failSafeCheck() throws {
        if position() == Point(x: 0, y: 0) {
            throw MouseError.failSafeTriggered
        }
    }

    public func move(to point: Point, duration: Double, easing: Easing) throws {
        try failSafeCheck()
        let start = position()

        if duration > Self.minimumDuration {
            let steps = max(2, Int((duration * stepsPerSecond).rounded()))
            let pause = duration / Double(steps)
            for n in 1..<steps {
                let t = easing.apply(Double(n) / Double(steps))
                let x = Double(start.x) + Double(point.x - start.x) * t
                let y = Double(start.y) + Double(point.y - start.y) * t
                try post(Point(x: Int(x.rounded()), y: Int(y.rounded())))
                Thread.sleep(forTimeInterval: pause)
            }
        }
        try post(point)
        sleep(callPause)
    }

    public func glide(to point: Point, duration: Double) throws {
        try failSafeCheck()
        let start = position()
        let steps = max(1, Int((duration * stepsPerSecond).rounded()))
        let pause = duration / Double(steps)
        for n in 1..<steps {
            let t = Double(n) / Double(steps)
            let x = Double(start.x) + Double(point.x - start.x) * t
            let y = Double(start.y) + Double(point.y - start.y) * t
            try post(Point(x: Int(x.rounded()), y: Int(y.rounded())))
            Thread.sleep(forTimeInterval: pause)
        }
        try post(point)
        Thread.sleep(forTimeInterval: pause)
    }

    public func click() throws {
        try failSafeCheck()
        let location = CGPoint(x: position().x, y: position().y)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: location, mouseButton: .left) else {
                throw MouseError.eventCreationFailed
            }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
        sleep(callPause)
    }

    public func sleep(_ seconds: Double) {
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
    }

    private func post(_ point: Point) throws {
        guard let event = CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: point.x, y: point.y), mouseButton: .left) else {
            throw MouseError.eventCreationFailed
        }
        event.post(tap: .cghidEventTap)
    }
}
