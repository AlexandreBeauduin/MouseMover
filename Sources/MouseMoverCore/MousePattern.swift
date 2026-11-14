import Foundation

/// Repere des points d'un motif : l'ecran entier, ou le curseur (au centre du repere) au debut du cycle.
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

/// Une etape du motif : aller au point, attendre eventuellement, puis cliquer eventuellement.
public struct PatternPoint: Codable, Equatable, Sendable {
    /// Position en fraction de l'ecran (0...1), (0, 0) en haut a gauche.
    public var x: Double
    public var y: Double
    public var click: Bool
    public var pause: PauseRange?
    /// Duree du deplacement, en secondes. `nil` : duree et courbe tirees au hasard, comme un humain.
    public var duration: Double?
    /// Garde sa place quand l'ordre du motif est melange.
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
    /// Melange l'ordre des points non fixes a chaque cycle.
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
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Motif"
        self.anchor = (try? container.decodeIfPresent(PatternAnchor.self, forKey: .anchor)) ?? .screen
        self.shuffle = (try? container.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? false
        let points = (try? container.decodeIfPresent([Lossy<PatternPoint>].self, forKey: .points)) ?? []
        self.points = points.compactMap(\.value)
        self = sanitized()
    }

    /// Ramene chaque valeur dans des bornes sures : un motif mal ecrit ne doit jamais bloquer la souris.
    public func sanitized() -> MousePattern {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty { copy.name = "Motif sans nom" }
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

    /// Ordre de passage : les points fixes gardent leur place, les autres sont melanges entre eux.
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

/// Decode un element sans faire echouer tout le tableau s'il est invalide.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Motifs integres

extension MousePattern {
    static let builtInPrefix = "builtin."

    /// Le cycle historique : centre, clic, quatre coins dans un ordre aleatoire, retour au centre.
    public static let classic = MousePattern(
        id: "builtin.classic", name: "Classique", shuffle: true,
        points: [
            PatternPoint(x: 0.5, y: 0.5, click: true, pause: PauseRange(min: 0.08, max: 0.18), fixed: true),
            PatternPoint(x: 0, y: 1, pause: PauseRange(min: 0.05, max: 0.25)),
            PatternPoint(x: 0, y: 0, pause: PauseRange(min: 0.05, max: 0.25)),
            PatternPoint(x: 1, y: 0, pause: PauseRange(min: 0.05, max: 0.25)),
            PatternPoint(x: 1, y: 1, pause: PauseRange(min: 0.05, max: 0.25)),
            PatternPoint(x: 0.5, y: 0.5, fixed: true),
        ])

    /// Quelques pixels autour du curseur, sans clic, puis retour exact a sa position.
    public static let discreet = MousePattern(
        id: "builtin.discreet", name: "Discret", anchor: .cursor,
        points: [
            PatternPoint(x: 0.502, y: 0.5, duration: 0.12),
            PatternPoint(x: 0.502, y: 0.503, duration: 0.12),
            PatternPoint(x: 0.499, y: 0.502, duration: 0.12),
            PatternPoint(x: 0.5, y: 0.5, duration: 0.12),
        ])

    /// Un tour d'ecran en cercle autour du centre, sans clic.
    public static let circle = MousePattern(
        id: "builtin.circle", name: "Cercle", points: circlePoints(count: 16, radius: 0.3))

    /// Balayage en zigzag de gauche a droite, sans clic.
    public static let zigzag = MousePattern(
        id: "builtin.zigzag", name: "Zigzag",
        points: stride(from: 0, through: 6, by: 1).map { step in
            PatternPoint(x: 0.1 + Double(step) * 0.8 / 6, y: step.isMultiple(of: 2) ? 0.3 : 0.7,
                         pause: PauseRange(min: 0.02, max: 0.1))
        } + [PatternPoint(x: 0.5, y: 0.5)])

    public static let builtIns: [MousePattern] = [classic, discreet, circle, zigzag]

    private static func circlePoints(count: Int, radius: Double) -> [PatternPoint] {
        (0...count).map { step in
            let angle = Double(step) / Double(count) * 2 * Double.pi
            // 9/16 : reste a peu pres rond sur un ecran 16:9.
            let x = ((0.5 + radius * cos(angle) * 9 / 16) * 1000).rounded() / 1000
            let y = ((0.5 + radius * sin(angle)) * 1000).rounded() / 1000
            return PatternPoint(x: x, y: y, duration: 0.09)
        }
    }
}
