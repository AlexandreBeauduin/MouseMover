import Foundation

/// Frame of a pattern's points: the whole display, or the cursor (at the center) when the cycle starts.
public enum PatternAnchor: String, Codable, CaseIterable, Sendable {
    case screen
    case cursor
}

public struct PauseRange: Equatable, Sendable {
    public var min: Double
    public var max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
}

/// One step of a pattern: go to the point, optionally wait, then optionally click.
public struct PatternPoint: Codable, Equatable, Sendable {
    /// Position as a fraction of the display (0...1), (0, 0) at the top left.
    public var x: Double
    public var y: Double
    public var click: Bool
    public var pause: PauseRange?
    /// Duration of the move, in seconds. `nil`: random duration and curve, like a human.
    public var duration: Double?
    /// Keeps its place when the pattern order is shuffled.
    public var fixed: Bool

    public init(x: Double, y: Double, click: Bool = false, pause: PauseRange? = nil,
                duration: Double? = nil, fixed: Bool = false) {
        self.x = x
        self.y = y
        self.click = click
        self.pause = pause
        self.duration = duration
        self.fixed = fixed
    }

    enum CodingKeys: String, CodingKey {
        case x, y, click, duration, fixed
        case pauseMin = "pause_min"
        case pauseMax = "pause_max"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.x = try container.decode(Double.self, forKey: .x)
        self.y = try container.decode(Double.self, forKey: .y)
        self.click = (try? container.decodeIfPresent(Bool.self, forKey: .click)) ?? false
        self.fixed = (try? container.decodeIfPresent(Bool.self, forKey: .fixed)) ?? false
        self.duration = (try? container.decodeIfPresent(Double.self, forKey: .duration)) ?? nil
        let pauseMin = (try? container.decodeIfPresent(Double.self, forKey: .pauseMin)) ?? nil
        let pauseMax = (try? container.decodeIfPresent(Double.self, forKey: .pauseMax)) ?? nil
        if let low = pauseMin ?? pauseMax {
            self.pause = PauseRange(min: low, max: pauseMax ?? low)
        } else {
            self.pause = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        if click { try container.encode(click, forKey: .click) }
        if fixed { try container.encode(fixed, forKey: .fixed) }
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(pause?.min, forKey: .pauseMin)
        try container.encodeIfPresent(pause?.max, forKey: .pauseMax)
    }
}

public struct MousePattern: Codable, Equatable, Identifiable, Sendable {
    public static let maxPoints = 200
    public static let durationRange = 0.05...3.0
    public static let maxPause = 5.0

    public var id: String
    public var name: String
    public var anchor: PatternAnchor
    /// Shuffles the order of the non-fixed points on each cycle.
    public var shuffle: Bool
    public var points: [PatternPoint]

    public init(id: String = UUID().uuidString, name: String, anchor: PatternAnchor = .screen,
                shuffle: Bool = false, points: [PatternPoint]) {
        self.id = id
        self.name = name
        self.anchor = anchor
        self.shuffle = shuffle
        self.points = points
    }

    public var isBuiltIn: Bool { id.hasPrefix(Self.builtInPrefix) }

    enum CodingKeys: String, CodingKey {
        case id, name, anchor, shuffle, points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? L10n.defaultPatternName
        self.anchor = (try? container.decodeIfPresent(PatternAnchor.self, forKey: .anchor)) ?? .screen
        self.shuffle = (try? container.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? false
        let points = (try? container.decodeIfPresent([Lossy<PatternPoint>].self, forKey: .points)) ?? []
        self.points = points.compactMap(\.value)
        self = sanitized()
    }

    /// Brings every value into safe bounds: a badly written pattern must never lock the mouse.
    public func sanitized() -> MousePattern {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty { copy.name = L10n.untitledPattern }
        copy.points = points.prefix(Self.maxPoints).compactMap { point in
            guard point.x.isFinite, point.y.isFinite else { return nil }
            var point = point
            point.x = Swift.min(Swift.max(point.x, 0), 1)
            point.y = Swift.min(Swift.max(point.y, 0), 1)
            if let duration = point.duration {
                point.duration = duration.isFinite
                    ? Swift.min(Swift.max(duration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
                    : nil
            }
            if let pause = point.pause {
                let low = pause.min.isFinite ? Swift.min(Swift.max(pause.min, 0), Self.maxPause) : 0
                let high = pause.max.isFinite ? Swift.min(Swift.max(pause.max, 0), Self.maxPause) : low
                point.pause = PauseRange(min: Swift.min(low, high), max: Swift.max(low, high))
            }
            return point
        }
        return copy
    }

    /// Playing order: fixed points keep their place, the others are shuffled among themselves.
    func order(shuffledBy random: RandomSource) -> [PatternPoint] {
        guard shuffle else { return points }
        let movableSlots = points.indices.filter { !points[$0].fixed }
        var result = points
        for (slot, point) in zip(movableSlots, random.shuffled(movableSlots.map { points[$0] })) {
            result[slot] = point
        }
        return result
    }
}

/// Decodes an element without failing the whole array when it is invalid.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Built-in patterns

extension MousePattern {
    static let builtInPrefix = "builtin."

    /// The original cycle: center, click, the four corners in random order, back to the center.
    public static var classic: MousePattern {
        MousePattern(
            id: "builtin.classic", name: L10n.patternClassic, shuffle: true,
            points: [
                PatternPoint(x: 0.5, y: 0.5, click: true, pause: PauseRange(min: 0.08, max: 0.18), fixed: true),
                PatternPoint(x: 0, y: 1, pause: PauseRange(min: 0.05, max: 0.25)),
                PatternPoint(x: 0, y: 0, pause: PauseRange(min: 0.05, max: 0.25)),
                PatternPoint(x: 1, y: 0, pause: PauseRange(min: 0.05, max: 0.25)),
                PatternPoint(x: 1, y: 1, pause: PauseRange(min: 0.05, max: 0.25)),
                PatternPoint(x: 0.5, y: 0.5, fixed: true),
            ])
    }

    /// A few pixels around the cursor, no click, then back to its exact position.
    public static var discreet: MousePattern {
        MousePattern(
            id: "builtin.discreet", name: L10n.patternDiscreet, anchor: .cursor,
            points: [
                PatternPoint(x: 0.502, y: 0.5, duration: 0.12),
                PatternPoint(x: 0.502, y: 0.503, duration: 0.12),
                PatternPoint(x: 0.499, y: 0.502, duration: 0.12),
                PatternPoint(x: 0.5, y: 0.5, duration: 0.12),
            ])
    }

    /// One circle around the center of the display, no click.
    public static var circle: MousePattern {
        MousePattern(id: "builtin.circle", name: L10n.patternCircle, points: circlePoints(count: 16, radius: 0.3))
    }

    /// A zigzag sweep from left to right, no click.
    public static var zigzag: MousePattern {
        MousePattern(
            id: "builtin.zigzag", name: L10n.patternZigzag,
            points: stride(from: 0, through: 6, by: 1).map { step in
                PatternPoint(x: 0.1 + Double(step) * 0.8 / 6, y: step.isMultiple(of: 2) ? 0.3 : 0.7,
                             pause: PauseRange(min: 0.02, max: 0.1))
            } + [PatternPoint(x: 0.5, y: 0.5)])
    }

    /// Computed so that names follow the current language.
    public static var builtIns: [MousePattern] { [classic, discreet, circle, zigzag] }

    private static func circlePoints(count: Int, radius: Double) -> [PatternPoint] {
        (0...count).map { step in
            let angle = Double(step) / Double(count) * 2 * Double.pi
            // 9/16: stays roughly round on a 16:9 display.
            let x = ((0.5 + radius * cos(angle) * 9 / 16) * 1000).rounded() / 1000
            let y = ((0.5 + radius * sin(angle)) * 1000).rounded() / 1000
            return PatternPoint(x: x, y: y, duration: 0.09)
        }
    }
}
