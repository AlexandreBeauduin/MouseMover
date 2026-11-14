import XCTest
@testable import MouseMoverCore

final class DisplayTests: XCTestCase {
    func testFloorDivMatchesPythonForNegatives() {
        XCTAssertEqual(floorDiv(7, 2), 3)
        XCTAssertEqual(floorDiv(-7, 2), -4)
        XCTAssertEqual(floorDiv(-8, 2), -4)
        XCTAssertEqual(floorDiv(0, 2), 0)
        XCTAssertEqual(floorDiv(-1, 2), -1)
    }

    func testBoundsAreInclusive() {
        let b = Fixtures.main.bounds
        XCTAssertEqual(b, DisplayBounds(minX: 0, maxX: 3199, minY: 0, maxY: 1799))
    }

    func testCenterOfMainDisplay() {
        XCTAssertEqual(Fixtures.main.bounds.center, Point(x: 1599, y: 899))
    }

    func testCenterWithNegativeOrigin() {
        // (-2560 + -1) // 2 = -1281 (not -1280); (0 + 1439) // 2 = 719
        XCTAssertEqual(Fixtures.left.bounds.center, Point(x: -1281, y: 719))
        // (-625 + 740) // 2 = 57; (-1024 + -1) // 2 = -513
        XCTAssertEqual(Fixtures.upperLeft.bounds.center, Point(x: 57, y: -513))
    }

    func testSortedLeftToRight() {
        let sorted = DisplayCatalog.sortedLeftToRight([Fixtures.main, Fixtures.upperLeft, Fixtures.left])
        XCTAssertEqual(sorted.map(\.id), [2, 3, 1])
    }

    func testSortIsStableForEqualX() {
        let a = DisplayInfo(id: 10, x: 0, y: 0, width: 100, height: 100, isMain: true)
        let b = DisplayInfo(id: 11, x: 0, y: 200, width: 100, height: 100, isMain: false)
        XCTAssertEqual(DisplayCatalog.sortedLeftToRight([a, b]).map(\.id), [10, 11])
        XCTAssertEqual(DisplayCatalog.sortedLeftToRight([b, a]).map(\.id), [11, 10])
    }

    func testLabels() {
        withLanguage(.fr) {
            XCTAssertEqual(DisplayCatalog.label(for: Fixtures.main, index: 3), "Écran 3 — 3200x1800 (principal)")
            XCTAssertEqual(DisplayCatalog.label(for: Fixtures.left, index: 1), "Écran 1 — 2560x1440")
        }
        withLanguage(.en) {
            XCTAssertEqual(DisplayCatalog.label(for: Fixtures.main, index: 3), "Display 3 — 3200x1800 (main)")
        }
    }

    func testResolveSelectedMainFallbackAndEmpty() {
        let all = [Fixtures.left, Fixtures.main]
        XCTAssertEqual(DisplayCatalog.resolve(selected: 2, in: all)?.id, 2)
        XCTAssertEqual(DisplayCatalog.resolve(selected: nil, in: all)?.id, 1)
        XCTAssertEqual(DisplayCatalog.resolve(selected: 999, in: all)?.id, 1)
        XCTAssertEqual(DisplayCatalog.resolve(selected: nil, in: [Fixtures.left])?.id, 2)
        XCTAssertNil(DisplayCatalog.resolve(selected: 1, in: []))
    }

    func testSystemProviderReturnsAtLeastOneMainDisplay() {
        let displays = SystemDisplayProvider().activeDisplays()
        XCTAssertFalse(displays.isEmpty)
        XCTAssertEqual(displays.filter(\.isMain).count, 1)
        XCTAssertEqual(displays.map(\.x), displays.map(\.x).sorted())
    }
}
