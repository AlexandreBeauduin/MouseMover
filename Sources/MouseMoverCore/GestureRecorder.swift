import Foundation

/// Une position du curseur relevee pendant l'enregistrement d'un geste.
public struct GestureSample: Equatable, Sendable {
    /// Secondes depuis le debut de l'enregistrement.
    public var time: Double
    public var point: Point
    /// Un clic gauche a eu lieu a cet instant.
    public var click: Bool

    public init(time: Double, point: Point, click: Bool = false) {
        self.time = time
        self.point = point
        self.click = click
    }
}

/// Transforme un geste enregistre en motif : arrets, clics et rythme conserves, trajet simplifie.
public enum GestureRecorder {
    /// En dessous (fraction de l'ecran), le curseur est considere immobile.
    static let stillness = 0.0015
    /// Un arret au moins aussi long devient une pause du motif.
    static let minimumPause = 0.2
    /// Ecart toleré entre le trajet reel et le trajet simplifie (fraction de l'ecran).
    static let tolerance = 0.004

    struct Node: Equatable {
        var x: Double
        var y: Double
        var start: Double
        var end: Double
        var click: Bool
    }

    public static func pattern(from samples: [GestureSample], in bounds: DisplayBounds,
                               name: String = "Geste enregistré") -> MousePattern? {
        var nodes = group(samples, in: bounds)
        guard !nodes.isEmpty else { return nil }
        // L'attente avant le premier mouvement et apres le dernier ne fait pas partie du geste.
        nodes[0].start = nodes[0].end
        nodes[nodes.count - 1].end = nodes[nodes.count - 1].start

        var epsilon = tolerance
        var kept = simplify(nodes, epsilon: epsilon)
        while kept.count > MousePattern.maxPoints, epsilon < 1 {
            epsilon *= 1.5
            kept = simplify(nodes, epsilon: epsilon)
        }
        if kept.count > MousePattern.maxPoints {
            kept = Array(kept.prefix(MousePattern.maxPoints - 1)) + [kept[kept.count - 1]]
        }

        var points: [PatternPoint] = []
        var previous: Node?
        for node in kept {
            let dwell = node.end - node.start
            var point = PatternPoint(
                x: rounded(node.x), y: rounded(node.y), click: node.click,
                pause: dwell >= minimumPause ? PauseRange(min: rounded(dwell), max: rounded(dwell)) : nil)
            if let previous {
                point.duration = rounded(node.start - previous.end)
            }
            points.append(point)
            previous = node
        }
        return MousePattern(name: name, points: points).sanitized()
    }

    /// Regroupe les releves successifs presque immobiles en un seul noeud (avec sa duree d'arret).
    static func group(_ samples: [GestureSample], in bounds: DisplayBounds) -> [Node] {
        let width = Double(max(bounds.maxX - bounds.minX, 1))
        let height = Double(max(bounds.maxY - bounds.minY, 1))
        var nodes: [Node] = []
        for sample in samples.sorted(by: { $0.time < $1.time }) {
            let x = min(max(Double(sample.point.x - bounds.minX) / width, 0), 1)
            let y = min(max(Double(sample.point.y - bounds.minY) / height, 0), 1)
            if var last = nodes.last, abs(last.x - x) <= stillness, abs(last.y - y) <= stillness,
               !(last.click && sample.click) {
                last.end = sample.time
                last.click = last.click || sample.click
                nodes[nodes.count - 1] = last
            } else {
                nodes.append(Node(x: x, y: y, start: sample.time, end: sample.time, click: sample.click))
            }
        }
        return nodes
    }

    /// Douglas-Peucker entre les noeuds incontournables (debut, fin, clics, pauses).
    static func simplify(_ nodes: [Node], epsilon: Double) -> [Node] {
        guard nodes.count > 2 else { return nodes }
        let anchors = nodes.indices.filter { index in
            index == 0 || index == nodes.count - 1 || nodes[index].click
                || nodes[index].end - nodes[index].start >= minimumPause
        }
        var keep = Set(anchors)
        for (from, to) in zip(anchors, anchors.dropFirst()) {
            reduce(nodes, from: from, to: to, epsilon: epsilon, keep: &keep)
        }
        return keep.sorted().map { nodes[$0] }
    }

    private static func reduce(_ nodes: [Node], from: Int, to: Int, epsilon: Double, keep: inout Set<Int>) {
        guard to - from > 1 else { return }
        var farthest = from
        var distance = 0.0
        for index in (from + 1)..<to {
            let d = distanceToSegment(nodes[index], nodes[from], nodes[to])
            if d > distance {
                distance = d
                farthest = index
            }
        }
        guard distance > epsilon else { return }
        keep.insert(farthest)
        reduce(nodes, from: from, to: farthest, epsilon: epsilon, keep: &keep)
        reduce(nodes, from: farthest, to: to, epsilon: epsilon, keep: &keep)
    }

    private static func distanceToSegment(_ p: Node, _ a: Node, _ b: Node) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
