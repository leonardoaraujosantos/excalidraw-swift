import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class FrameTests: XCTestCase {
    private func frame(_ id: String, x: Double, y: Double, w: Double, h: Double) -> ExcalidrawElement {
        var b = BaseProperties(id: id); b.x = x; b.y = y; b.width = w; b.height = h
        return ExcalidrawElement(base: b, kind: .frame(name: nil))
    }

    private func rect(_ id: String, x: Double, y: Double, w: Double = 30, h: Double = 30) -> ExcalidrawElement {
        var b = BaseProperties(id: id); b.x = x; b.y = y; b.width = w; b.height = h; b.backgroundColor = "#ff0000"
        return ExcalidrawElement(base: b, kind: .rectangle)
    }

    private func editor(_ elements: [ExcalidrawElement]) -> EditorController {
        var idCount = 0
        return EditorController(scene: Scene(elements: elements), idProvider: { idCount += 1; return "n\(idCount)" })
    }

    func testFrameContainmentHelper() {
        let frameEl = frame("f", x: 0, y: 0, w: 200, h: 200)
        let inside = rect("a", x: 50, y: 50)
        let outside = rect("b", x: 300, y: 300)
        XCTAssertEqual(Frames.frame(containing: inside, in: [frameEl, inside]), "f")
        XCTAssertNil(Frames.frame(containing: outside, in: [frameEl, outside]))
        XCTAssertNil(Frames.frame(containing: frameEl, in: [frameEl])) // frames don't nest into themselves
    }

    func testElementGainsFrameIdWhenDraggedIn() {
        let ec = editor([frame("frame1", x: 0, y: 0, w: 200, h: 200), rect("r", x: 400, y: 400)])
        // Drag "r" into the frame.
        ec.pointerDown(PointerEvent(scenePoint: Point(415, 415), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(115, 115), phase: .move)) // r centre → (100,100), inside frame
        ec.pointerUp(PointerEvent(scenePoint: Point(115, 115), phase: .up))
        XCTAssertEqual(ec.scene.element(id: "r")?.base.frameId, "frame1")
    }

    func testMovingFrameMovesChildren() {
        var child = rect("c", x: 50, y: 50)
        child.base.frameId = "frame1"
        let ec = editor([frame("frame1", x: 0, y: 0, w: 200, h: 200), child])
        // Grab the frame border (top edge at y=0) and drag down by 100.
        ec.pointerDown(PointerEvent(scenePoint: Point(100, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(100, 100), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(100, 100), phase: .up))
        XCTAssertEqual(ec.scene.element(id: "frame1")?.base.y ?? .nan, 100, accuracy: 1e-6)
        XCTAssertEqual(ec.scene.element(id: "c")?.base.y ?? .nan, 150, accuracy: 1e-6) // child followed
    }

    func testCreateFrameTool() {
        let ec = editor([])
        ec.setTool(.frame)
        ec.pointerDown(PointerEvent(scenePoint: Point(0, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(200, 150), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(200, 150), phase: .up))
        guard case .frame = ec.scene.visibleElements.first?.kind else { return XCTFail("frame") }
        XCTAssertEqual(ec.scene.visibleElements.first?.base.width, 200)
    }
}
