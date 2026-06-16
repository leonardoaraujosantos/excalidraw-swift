import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class ShapeRecognitionTests: XCTestCase {
    private func freedraw(_ corners: [Point], closed: Bool) -> EditorController {
        var path = corners
        if closed { path.append(corners[0]) }
        var points: [Point] = []
        for i in 0 ..< (path.count - 1) {
            let a = path[i], b = path[i + 1]
            for s in 0 ..< 12 {
                let t = Double(s) / 12
                points.append(Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
            }
        }
        points.append(path.last!)
        var base = BaseProperties(id: "f"); base.strokeColor = "#e03131"; base.strokeWidth = 3
        let props = FreedrawProperties(points: points, pressures: [], simulatePressure: true)
        return EditorController(scene: Scene(elements: [ExcalidrawElement(base: base, kind: .freedraw(props))]))
    }

    func testReplacesSquareStrokeWithRectangle() {
        let ec = freedraw([Point(10, 10), Point(110, 10), Point(110, 110), Point(10, 110)], closed: true)
        XCTAssertEqual(ec.recognizeFreedraw("f"), .rectangle)
        guard let element = ec.scene.element(id: "f") else { return XCTFail("missing") }
        if case .rectangle = element.kind {} else { XCTFail("expected a rectangle") }
        // Bounds preserved and style carried over.
        XCTAssertEqual(element.base.width, 100, accuracy: 5)
        XCTAssertEqual(element.base.strokeColor, "#e03131")
        XCTAssertEqual(ec.selectedIDs, ["f"])
    }

    func testReplacesTriangleStrokeWithClosedPolyline() {
        let ec = freedraw([Point(50, 0), Point(100, 100), Point(0, 100)], closed: true)
        XCTAssertEqual(ec.recognizeFreedraw("f"), .triangle)
        guard case let .line(props) = ec.scene.element(id: "f")?.kind else { return XCTFail("expected a line") }
        XCTAssertTrue(props.polygon)
        XCTAssertEqual(props.points.count, 4) // 3 corners + closing point
    }

    func testRecognitionIsUndoable() {
        let ec = freedraw([Point(10, 10), Point(110, 10), Point(110, 110), Point(10, 110)], closed: true)
        ec.recognizeFreedraw("f")
        XCTAssertTrue(ec.undo())
        guard case .freedraw = ec.scene.element(id: "f")?.kind else { return XCTFail("should revert to freedraw") }
    }

    func testReplacesStarStrokeWithClosedPolyline() {
        // Trace a generated 5-point star as a freehand stroke.
        let box = BoundingBox(minX: 0, minY: 0, maxX: 200, maxY: 200)
        var path = ShapeGenerator.star(points: 5, in: box)
        path.append(path[0])
        var points: [Point] = []
        for i in 0 ..< (path.count - 1) {
            let a = path[i], b = path[i + 1]
            for s in 0 ..< 6 {
                let t = Double(s) / 6
                points.append(Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
            }
        }
        var base = BaseProperties(id: "f"); base.strokeColor = "#1971c2"
        let ec = EditorController(scene: Scene(elements: [
            ExcalidrawElement(base: base, kind: .freedraw(FreedrawProperties(points: points)))
        ]))
        XCTAssertEqual(ec.recognizeFreedraw("f"), .star)
        guard case let .line(props) = ec.scene.element(id: "f")?.kind else { return XCTFail("expected a line") }
        XCTAssertTrue(props.polygon)
        XCTAssertEqual(props.points.count, 11) // 10 star vertices + closing point
        XCTAssertEqual(ec.scene.element(id: "f")?.base.strokeColor, "#1971c2")
    }

    func testIgnoresNonFreedraw() {
        let ec = EditorController(scene: Scene(elements: [
            ExcalidrawElement(base: BaseProperties(id: "r"), kind: .rectangle)
        ]))
        XCTAssertNil(ec.recognizeFreedraw("r"))
    }
}
