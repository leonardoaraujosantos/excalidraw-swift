import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class TransformTests: XCTestCase {
    private let box = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 100)

    func testResizeCorner() {
        let r = Transform.resize(box, handle: .bottomRight, to: Point(150, 150))
        XCTAssertEqual(r, BoundingBox(minX: 0, minY: 0, maxX: 150, maxY: 150))
    }

    func testResizeTopLeftMovesOrigin() {
        let r = Transform.resize(box, handle: .topLeft, to: Point(-20, -10))
        XCTAssertEqual(r, BoundingBox(minX: -20, minY: -10, maxX: 100, maxY: 100))
    }

    func testResizeFromCenter() {
        let r = Transform.resize(box, handle: .bottomRight, to: Point(60, 60), fromCenter: true)
        XCTAssertEqual(r, BoundingBox(minX: 40, minY: 40, maxX: 60, maxY: 60))
    }

    func testResizeKeepAspect() {
        let wide = BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 50) // ratio 2
        let r = Transform.resize(wide, handle: .bottomRight, to: Point(200, 60), keepAspect: true)
        XCTAssertEqual(r.width / r.height, 2, accuracy: 1e-9)
        XCTAssertEqual(r, BoundingBox(minX: 0, minY: 0, maxX: 200, maxY: 100))
    }

    func testResizeClampsMinSize() {
        let r = Transform.resize(box, handle: .bottomRight, to: Point(0, 0))
        XCTAssertEqual(r.width, Transform.minSize, accuracy: 1e-9)
        XCTAssertEqual(r.height, Transform.minSize, accuracy: 1e-9)
    }

    func testResizeNormalizesFlip() {
        let r = Transform.resize(box, handle: .right, to: Point(-50, 50))
        XCTAssertEqual(r.minX, -50)
        XCTAssertEqual(r.maxX, 0)
    }

    func testScaleBoxElement() {
        var b = BaseProperties(id: "r"); b.x = 10; b.y = 10; b.width = 20; b.height = 20
        let e = Transform.scale(
            ExcalidrawElement(base: b, kind: .rectangle),
            from: box, to: BoundingBox(minX: 0, minY: 0, maxX: 200, maxY: 200)
        )
        XCTAssertEqual(e.base.x, 20)
        XCTAssertEqual(e.base.width, 40)
    }

    func testScaleLinearPoints() {
        let b = BaseProperties(id: "l")
        let line = LinearProperties(points: [Point(0, 0), Point(10, 5)])
        let e = Transform.scale(
            ExcalidrawElement(base: b, kind: .line(line)),
            from: BoundingBox(minX: 0, minY: 0, maxX: 10, maxY: 5),
            to: BoundingBox(minX: 0, minY: 0, maxX: 20, maxY: 10)
        )
        _ = b
        guard case let .line(scaled) = e.kind else { return XCTFail("line") }
        XCTAssertEqual(scaled.points[1], Point(20, 10))
    }

    func testScaleTextScalesFontSize() {
        var b = BaseProperties(id: "t"); b.width = 100; b.height = 40
        let text = TextProperties(fontSize: 20, text: "Hi")
        let e = Transform.scale(
            ExcalidrawElement(base: b, kind: .text(text)),
            from: BoundingBox(minX: 0, minY: 0, maxX: 100, maxY: 40),
            to: BoundingBox(minX: 0, minY: 0, maxX: 200, maxY: 80) // 2× height
        )
        guard case let .text(scaled) = e.kind else { return XCTFail("text") }
        XCTAssertEqual(scaled.fontSize, 40, accuracy: 1e-9) // font doubled with height
    }

    func testTranslate() {
        var b = BaseProperties(id: "r"); b.x = 5; b.y = 5
        let e = Transform.translate(ExcalidrawElement(base: b, kind: .rectangle), dx: 10, dy: -3)
        XCTAssertEqual(e.base.x, 15)
        XCTAssertEqual(e.base.y, 2)
    }

    func testRotationAngle() {
        // Handle directly above the centre means angle 0.
        let up = Transform.rotationAngle(center: Point(50, 50), pointer: Point(50, 0), snap: false)
        XCTAssertEqual(up, 0, accuracy: 1e-9)
        // Pointer to the right means a quarter turn.
        let right = Transform.rotationAngle(center: Point(50, 50), pointer: Point(100, 50), snap: false)
        XCTAssertEqual(right, .pi / 2, accuracy: 1e-9)
    }

    func testRotationSnap() {
        let angle = Transform.rotationAngle(center: Point(0, 0), pointer: Point(2, -10), snap: true)
        let step = Double.pi / 12
        XCTAssertEqual((angle / step).rounded() * step, angle, accuracy: 1e-9)
    }

    func testHandlePositions() {
        let h = Transform.handlePositions(for: box, rotationOffset: 30)
        XCTAssertEqual(h.count, 9)
        XCTAssertEqual(h[.topLeft], Point(0, 0))
        XCTAssertEqual(h[.bottomRight], Point(100, 100))
        XCTAssertEqual(h[.rotation], Point(50, -30))
    }
}
