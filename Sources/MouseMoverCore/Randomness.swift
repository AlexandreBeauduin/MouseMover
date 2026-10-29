import Foundation

public protocol RandomSource: AnyObject {
    func int(in range: ClosedRange<Int>) -> Int
    func double(in range: ClosedRange<Double>) -> Double
    func shuffled<T>(_ items: [T]) -> [T]
    func choice<T>(_ items: [T]) -> T
}

public final class SystemRandom: RandomSource {
    public init() {}

    public func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range) }
    public func double(in range: ClosedRange<Double>) -> Double { Double.random(in: range) }
    public func shuffled<T>(_ items: [T]) -> [T] { items.shuffled() }
    public func choice<T>(_ items: [T]) -> T { items.randomElement()! }
}
