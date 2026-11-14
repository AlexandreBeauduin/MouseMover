import Foundation
@testable import MouseMoverCore

/// Runs `body` with the UI language forced, so string assertions do not depend on the machine.
func withLanguage<T>(_ language: Language, _ body: () throws -> T) rethrows -> T {
    let saved = L10n.language
    defer { L10n.language = saved }
    L10n.language = language
    return try body()
}

/// UserDefaults that never touches the disk. A real suite, even removed with
/// `removePersistentDomain`, leaves an empty plist in ~/Library/Preferences on every run.
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var storage: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { storage[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { storage[defaultName] = value }
    override func removeObject(forKey defaultName: String) { storage[defaultName] = nil }
    override func bool(forKey defaultName: String) -> Bool { storage[defaultName] as? Bool ?? false }
    override func string(forKey defaultName: String) -> String? { storage[defaultName] as? String }
}

final class FakeMouseDriver: MouseDriver {
    enum Event: Equatable {
        case move(Point, Double, Easing)
        case glide(Point, Double)
        case click
        case sleep(Double)
    }

    var events: [Event] = []
    var current = Point(x: 500, y: 500)
    /// Throws `error` on the Nth action (move or click), counting from 1.
    var failOnAction: Int?
    var error: Error = MouseError.failSafeTriggered
    private var actionCount = 0

    func position() -> Point { current }

    func move(to point: Point, duration: Double, easing: Easing) throws {
        try checkFailure()
        current = point
        events.append(.move(point, duration, easing))
    }

    func glide(to point: Point, duration: Double) throws {
        try checkFailure()
        current = point
        events.append(.glide(point, duration))
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
        events.compactMap {
            switch $0 {
            case .move(let p, _, _), .glide(let p, _): p
            default: nil
            }
        }
    }

    var clickCount: Int { events.filter { $0 == .click }.count }
}

/// Deterministic random source: minimal values, unchanged order, first choice. Logs every call.
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
    private(set) var ranPatterns: [MousePattern] = []
    private var completions: [@MainActor () -> Void] = []

    func runCycle(_ pattern: MousePattern, on display: DisplayInfo, displays: [DisplayInfo],
                  completion: @escaping @MainActor () -> Void) {
        ranOn.append(display)
        ranPatterns.append(pattern)
        completions.append(completion)
    }

    func finishAll() {
        let pending = completions
        completions = []
        pending.forEach { $0() }
    }
}

enum Fixtures {
    // A real setup: main 3200x1800 at (0,0), one display on the left, one above on the left.
    static let main = DisplayInfo(id: 1, x: 0, y: 0, width: 3200, height: 1800, isMain: true)
    static let left = DisplayInfo(id: 2, x: -2560, y: 0, width: 2560, height: 1440, isMain: false)
    static let upperLeft = DisplayInfo(id: 3, x: -625, y: -1024, width: 1366, height: 1024, isMain: false)

    static func tempURL(_ name: String = "config.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseMoverTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
