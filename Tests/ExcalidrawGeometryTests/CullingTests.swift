import ExcalidrawModel
import XCTest
@testable import ExcalidrawGeometry

final class CullingTests: XCTestCase {
    private func rect(_ id: String, x: Double, y: Double, w: Double = 50, h: Double = 50) -> ExcalidrawElement {
        var b = BaseProperties(id: id); b.x = x; b.y = y; b.width = w; b.height = h
        return ExcalidrawElement(base: b, kind: .rectangle)
    }

    func testKeepsOnScreenDropsOffScreen() {
        let visible = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 100)
        let onScreen = rect("on", x: 10, y: 10)
        let offScreen = rect("off", x: 1000, y: 1000)
        let result = Culling.visible([onScreen, offScreen], in: visible)
        XCTAssertEqual(result.map(\.id), ["on"])
    }

    func testKeepsPartiallyOverlappingElement() {
        let visible = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 100)
        let straddling = rect("edge", x: 80, y: 80) // extends past the edge but overlaps
        XCTAssertEqual(Culling.visible([straddling], in: visible).count, 1)
    }

    func testMarginKeepsNearbyElement() {
        let visible = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 100)
        let nearby = rect("near", x: 130, y: 10, w: 10, h: 10) // 30 units past the right edge
        XCTAssertTrue(Culling.visible([nearby], in: visible, margin: 0).isEmpty)
        XCTAssertEqual(Culling.visible([nearby], in: visible, margin: 100).count, 1)
    }
}
