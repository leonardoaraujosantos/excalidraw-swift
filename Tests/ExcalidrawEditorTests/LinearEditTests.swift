import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class LinearEditTests: XCTestCase {
    /// A 3-point line at origin: (0,0) (50,0) (100,0).
    private func lineEditor() -> EditorController {
        var base = BaseProperties(id: "L"); base.width = 100; base.height = 0
        let props = LinearProperties(points: [Point(0, 0), Point(50, 0), Point(100, 0)])
        let element = ExcalidrawElement(base: base, kind: .line(props))
        var idCount = 0
        return EditorController(scene: Scene(elements: [element]), idProvider: { idCount += 1; return "n\(idCount)" })
    }

    private func linePoints(_ ec: EditorController) -> [Point] {
        guard case let .line(props) = ec.scene.element(id: "L")?.kind else { return [] }
        return props.points
    }

    func testBeginLinearEditOnLine() {
        let ec = lineEditor()
        XCTAssertTrue(ec.beginLinearEdit(at: Point(50, 0)))
        XCTAssertEqual(ec.editingLinearID, "L")
        XCTAssertNotNil(ec.linearEditHandles())
        // No box transform handles while point-editing.
        XCTAssertTrue(ec.transformHandles().isEmpty)
    }

    func testDragAPointMovesIt() {
        let ec = lineEditor()
        ec.beginLinearEdit(at: Point(50, 0))
        // Grab the middle point (50,0) and drag it down to (50,40).
        ec.pointerDown(PointerEvent(scenePoint: Point(50, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(50, 40), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(50, 40), phase: .up))
        XCTAssertEqual(linePoints(ec)[1], Point(50, 40))
    }

    func testDragMidpointInsertsPoint() {
        let ec = lineEditor()
        ec.beginLinearEdit(at: Point(50, 0))
        // The midpoint between (0,0) and (50,0) is (25,0); dragging it inserts a point.
        ec.pointerDown(PointerEvent(scenePoint: Point(25, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(25, 30), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(25, 30), phase: .up))
        let pts = linePoints(ec)
        XCTAssertEqual(pts.count, 4) // inserted one
        XCTAssertEqual(pts[1], Point(25, 30))
    }

    func testEditIsUndoable() {
        let ec = lineEditor()
        ec.beginLinearEdit(at: Point(50, 0))
        ec.pointerDown(PointerEvent(scenePoint: Point(50, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(50, 40), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(50, 40), phase: .up))
        XCTAssertTrue(ec.undo())
        XCTAssertEqual(linePoints(ec)[1], Point(50, 0))
    }

    func testClickAwayExitsEdit() {
        let ec = lineEditor()
        ec.beginLinearEdit(at: Point(50, 0))
        XCTAssertEqual(ec.editingLinearID, "L")
        // Click far from any point/midpoint → leaves edit mode.
        ec.pointerDown(PointerEvent(scenePoint: Point(500, 500), phase: .down))
        XCTAssertNil(ec.editingLinearID)
    }

    func testChangingToolExitsEdit() {
        let ec = lineEditor()
        ec.beginLinearEdit(at: Point(50, 0))
        ec.setTool(.rectangle)
        XCTAssertNil(ec.editingLinearID)
    }
}
