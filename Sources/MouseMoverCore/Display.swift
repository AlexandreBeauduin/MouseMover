import CoreGraphics
import Foundation

public struct DisplayBounds: Equatable, Sendable {
    public let minX: Int
    public let maxX: Int
    public let minY: Int
    public let maxY: Int

    public init(minX: Int, maxX: Int, minY: Int, maxY: Int) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    public var center: Point {
        Point(x: floorDiv(minX + maxX, 2), y: floorDiv(minY + maxY, 2))
    }

    public func contains(_ point: Point) -> Bool {
        (minX...maxX).contains(point.x) && (minY...maxY).contains(point.y)
    }
}

public struct Point: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Division entiere arrondie vers le bas (comme `//` en Python), y compris pour les negatifs.
func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

public struct DisplayInfo: Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let isMain: Bool

    public init(id: UInt32, x: Int, y: Int, width: Int, height: Int, isMain: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isMain = isMain
    }

    public var bounds: DisplayBounds {
        DisplayBounds(minX: x, maxX: x + width - 1, minY: y, maxY: y + height - 1)
    }
}

public protocol DisplayProviding {
    func activeDisplays() -> [DisplayInfo]
}

public struct SystemDisplayProvider: DisplayProviding {
    public init() {}

    public func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }

        let mainID = CGMainDisplayID()
        let displays = ids.prefix(Int(count)).map { id -> DisplayInfo in
            let bounds = CGDisplayBounds(id)
            return DisplayInfo(
                id: id,
                x: Int(bounds.origin.x),
                y: Int(bounds.origin.y),
                width: Int(bounds.size.width),
                height: Int(bounds.size.height),
                isMain: id == mainID)
        }
        return DisplayCatalog.sortedLeftToRight(displays)
    }
}

public enum DisplayCatalog {
    public static func sortedLeftToRight(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        displays.enumerated()
            .sorted { ($0.element.x, $0.offset) < ($1.element.x, $1.offset) }
            .map(\.element)
    }

    /// `index` est la position (1, 2, 3...) dans la liste triee de gauche a droite.
    public static func label(for display: DisplayInfo, index: Int) -> String {
        L10n.displayLabel(index: index, width: display.width, height: display.height, isMain: display.isMain)
    }

    /// Ecran cible : celui choisi s'il existe encore, sinon l'ecran principal. `nil` si aucun ecran actif.
    public static func resolve(selected: UInt32?, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let selected, let match = displays.first(where: { $0.id == selected }) {
            return match
        }
        return displays.first(where: \.isMain) ?? displays.first
    }
}
