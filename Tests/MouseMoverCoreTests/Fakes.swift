import Foundation
@testable import MouseMoverCore

final class FakeMouseDriver: MouseDriver {
    enum Event: Equatable {
        case move(Point, Double, Easing)
        case click
        case sleep(Double)
    }

    var events: [Event] = []
    var current = Point(x: 500, y: 500)
    /// Leve `error` a la N-ieme action (deplacement ou clic), en comptant depuis 1.
    var failOnAction: Int?
    var error: Error = MouseError.failSafeTriggered
    private var actionCount = 0

    func position() -> Point { current }

    func move(to point: Point, duration: Double, easing: Easing) throws {
        try checkFailure()
        current = point
        events.append(.move(point, duration, easing))
    }

    func click() throws {
        try checkFailure()
        events.append(.click)
    }

    func sleep(_ seconds: Double) {
        events.append(.sleep(seconds))
    }

    private func checkFailure() throws {
        actionCount += 1
        if actionCount == failOnAction { throw error }
    }

    var moves: [Point] {
        events.compactMap { if case .move(let p, _, _) = $0 { return p } else { return nil } }
    }

    var clickCount: Int { events.filter { $0 == .click }.count }
}

/// Source aleatoire deterministe : valeurs minimales, ordre inchange, premier choix. Journalise chaque appel.
final class FakeRandom: RandomSource {
    var calls: [String] = []
    var intValue: Int?
    var doubleValue: Double?
    var reversed = false

    func int(in range: ClosedRange<Int>) -> Int {
        calls.append("int \(range.lowerBound)...\(range.upperBound)")
        return intValue ?? range.lowerBound
    }

    func double(in range: ClosedRange<Double>) -> Double {
        calls.append("double \(range.lowerBound)...\(range.upperBound)")
        return doubleValue ?? range.lowerBound
    }

    func shuffled<T>(_ items: [T]) -> [T] {
        calls.append("shuffled \(items.count)")
        return reversed ? items.reversed() : items
    }

    func choice<T>(_ items: [T]) -> T {
        calls.append("choice \(items.count)")
        return items[0]
    }
}

struct FakeDisplayProvider: DisplayProviding {
    var displays: [DisplayInfo]
    func activeDisplays() -> [DisplayInfo] { displays }
}

final class MutableDisplayProvider: DisplayProviding {
    var displays: [DisplayInfo]
    init(_ displays: [DisplayInfo]) { self.displays = displays }
    func activeDisplays() -> [DisplayInfo] { displays }
}

final class FakeLoginItem: LoginItemManaging {
    var isEnabled: Bool
    var failure: Error?
    private(set) var setCalls: [Bool] = []

    init(isEnabled: Bool = false) { self.isEnabled = isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
final class FakeCycleRunner: CycleRunning {
    private(set) var ranOn: [DisplayInfo] = []
    private var completions: [@MainActor () -> Void] = []

    func runCycle(on display: DisplayInfo, completion: @escaping @MainActor () -> Void) {
        ranOn.append(display)
        completions.append(completion)
    }

    func finishAll() {
        let pending = completions
        completions = []
        pending.forEach { $0() }
    }
}

enum Fixtures {
    // Configuration reelle de l'utilisateur : principal 3200x1800 en (0,0), un ecran a gauche, un au-dessus a gauche.
    static let main = DisplayInfo(id: 1, x: 0, y: 0, width: 3200, height: 1800, isMain: true)
    static let left = DisplayInfo(id: 2, x: -2560, y: 0, width: 2560, height: 1440, isMain: false)
    static let upperLeft = DisplayInfo(id: 3, x: -625, y: -1024, width: 1366, height: 1024, isMain: false)

    static func tempURL(_ name: String = "config.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseMoverTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
