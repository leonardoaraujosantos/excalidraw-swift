import ExcalidrawMath
import XCTest
@testable import ExcalidrawGeometry

final class BoundingBoxTests: XCTestCase {
    func testFromPoints() throws {
        let box = try XCTUnwrap(BoundingBox(points: [Point(1, 2), Point(-3, 5), Point(4, -1)]))
        XCTAssertEqual(box.minX, -3)
        XCTAssertEqual(box.minY, -1)
        XCTAssertEqual(box.maxX, 4)
        XCTAssertEqual(box.maxY, 5)
        XCTAssertEqual(box.width, 7)
        XCTAssertEqual(box.height, 6)
    }

    func testEmptyPointsIsNil() {
        XCTAssertNil(BoundingBox(points: []))
    }

    func testContains() {
        let box = BoundingBox(minX: 0, minY: 0, maxX: 10, maxY: 10)
        XCTAssertTrue(box.contains(Point(5, 5)))
        XCTAssertFalse(box.contains(Point(11, 5)))
    }

    func testUnion() {
        let a = BoundingBox(minX: 0, minY: 0, maxX: 2, maxY: 2)
        let b = BoundingBox(minX: 1, minY: 1, maxX: 4, maxY: 5)
        let u = a.union(b)
        XCTAssertEqual(u, BoundingBox(minX: 0, minY: 0, maxX: 4, maxY: 5))
    }
}
