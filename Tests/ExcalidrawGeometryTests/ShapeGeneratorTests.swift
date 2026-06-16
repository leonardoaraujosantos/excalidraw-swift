import ExcalidrawMath
import XCTest
@testable import ExcalidrawGeometry

final class ShapeGeneratorTests: XCTestCase {
    private let box = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 100)

    private func assertWithinBox(_ pts: [Point], tol: Double = 0.5) {
        for p in pts {
            XCTAssertGreaterThanOrEqual(p.x, box.minX - tol)
            XCTAssertLessThanOrEqual(p.x, box.maxX + tol)
            XCTAssertGreaterThanOrEqual(p.y, box.minY - tol)
            XCTAssertLessThanOrEqual(p.y, box.maxY + tol)
        }
    }

    func testRegularPolygonVertexCount() {
        XCTAssertEqual(ShapeGenerator.regularPolygon(sides: 5, in: box).count, 5)
        XCTAssertEqual(ShapeGenerator.regularPolygon(sides: 6, in: box).count, 6)
        assertWithinBox(ShapeGenerator.regularPolygon(sides: 6, in: box))
    }

    func testStarHasTwiceThePointsAndAlternatingRadii() {
        let star = ShapeGenerator.star(points: 5, in: box)
        XCTAssertEqual(star.count, 10)
        let c = Point(50, 50)
        let radii = star.map { $0.distance(to: c) }
        // Tips (even indices) are farther than valleys (odd indices).
        XCTAssertGreaterThan(radii[0], radii[1])
        assertWithinBox(star)
    }

    func testHeartAndCloudAndBubbleFitBox() {
        assertWithinBox(ShapeGenerator.heart(in: box))
        assertWithinBox(ShapeGenerator.cloud(in: box))
        assertWithinBox(ShapeGenerator.speechBubble(in: box))
        XCTAssertGreaterThan(ShapeGenerator.heart(in: box).count, 10)
        XCTAssertGreaterThan(ShapeGenerator.cloud(in: box).count, 10)
    }
}
