import ExcalidrawModel
import XCTest
@testable import ExcalidrawGeometry

final class DirtyRegionTests: XCTestCase {
    private func rect(_ id: String, x: Double, y: Double, w: Double = 40, h: Double = 40) -> ExcalidrawElement {
        var b = BaseProperties(id: id); b.x = x; b.y = y; b.width = w; b.height = h
        return ExcalidrawElement(base: b, kind: .rectangle)
    }

    func testNilWhenNothingChanges() {
        let scene = [rect("a", x: 0, y: 0)]
        XCTAssertNil(DirtyRegion.changed(from: scene, to: scene))
    }

    func testAddedElementRegion() {
        let region = DirtyRegion.changed(from: [], to: [rect("a", x: 10, y: 20)])
        XCTAssertEqual(region, BoundingBox(minX: 10, minY: 20, maxX: 50, maxY: 60))
    }

    func testRemovedElementRegion() {
        let region = DirtyRegion.changed(from: [rect("a", x: 10, y: 20)], to: [])
        XCTAssertEqual(region, BoundingBox(minX: 10, minY: 20, maxX: 50, maxY: 60))
    }

    func testMovedElementUnionsOldAndNewBounds() {
        let old = [rect("a", x: 0, y: 0)]
        let new = [rect("a", x: 100, y: 0)]
        // Union spans from the old position to the new one.
        XCTAssertEqual(DirtyRegion.changed(from: old, to: new), BoundingBox(minX: 0, minY: 0, maxX: 140, maxY: 40))
    }

    func testUnaffectedElementsAreIgnored() {
        let old = [rect("a", x: 0, y: 0), rect("b", x: 500, y: 500)]
        let new = [rect("a", x: 0, y: 10), rect("b", x: 500, y: 500)]
        // Only "a" changed → region near "a", not "b".
        let region = DirtyRegion.changed(from: old, to: new)
        XCTAssertEqual(region, BoundingBox(minX: 0, minY: 0, maxX: 40, maxY: 50))
    }
}
