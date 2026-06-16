import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class ImageCropTests: XCTestCase {
    private func imageEditor() -> EditorController {
        var base = BaseProperties(id: "img"); base.width = 100; base.height = 100
        let element = ExcalidrawElement(base: base, kind: .image(ImageProperties(fileId: "f", status: .saved)))
        return EditorController(scene: Scene(elements: [element]))
    }

    func testSetAndClearCrop() {
        let ec = imageEditor()
        let crop = ImageCrop(x: 10, y: 20, width: 50, height: 40, naturalWidth: 100, naturalHeight: 100)
        ec.setCrop(id: "img", crop)
        guard case let .image(props) = ec.scene.element(id: "img")?.kind else { return XCTFail("image") }
        XCTAssertEqual(props.crop, crop)

        ec.setCrop(id: "img", nil)
        guard case let .image(cleared) = ec.scene.element(id: "img")?.kind else { return XCTFail("image") }
        XCTAssertNil(cleared.crop)
    }

    func testCropIsUndoable() {
        let ec = imageEditor()
        let crop = ImageCrop(x: 5, y: 5, width: 20, height: 20, naturalWidth: 100, naturalHeight: 100)
        ec.setCrop(id: "img", crop)
        XCTAssertTrue(ec.undo())
        guard case let .image(props) = ec.scene.element(id: "img")?.kind else { return XCTFail("image") }
        XCTAssertNil(props.crop)
    }

    func testSetCropIgnoresNonImage() {
        var base = BaseProperties(id: "r")
        let ec = EditorController(scene: Scene(elements: [ExcalidrawElement(base: base, kind: .rectangle)]))
        _ = base
        ec.setCrop(id: "r", ImageCrop(x: 0, y: 0, width: 1, height: 1, naturalWidth: 1, naturalHeight: 1))
        XCTAssertFalse(ec.canUndo) // no-op, nothing recorded
    }

    // MARK: Interactive crop mode

    func testBeginCropEditRejectsNonImage() {
        let base = BaseProperties(id: "r")
        let ec = EditorController(scene: Scene(elements: [ExcalidrawElement(base: base, kind: .rectangle)]))
        XCTAssertFalse(ec.beginCropEdit(id: "r", naturalWidth: 100, naturalHeight: 100))
        XCTAssertNil(ec.editingCropID)
    }

    func testBeginCropEditEntersModeWithHandles() {
        let ec = imageEditor()
        XCTAssertTrue(ec.beginCropEdit(id: "img", naturalWidth: 200, naturalHeight: 200))
        XCTAssertEqual(ec.editingCropID, "img")
        XCTAssertEqual(ec.selectedIDs, ["img"])
        XCTAssertEqual(ec.cropEditHandles()?.count, 8)
        XCTAssertTrue(ec.transformHandles().isEmpty) // normal handles suppressed
    }

    func testDraggingHandleCropsImage() {
        let ec = imageEditor() // 100×100 image, no crop yet
        ec.beginCropEdit(id: "img", naturalWidth: 200, naturalHeight: 200)
        // Grab the left-edge handle at (0,50) and drag 10 units inward.
        ec.pointerDown(PointerEvent(scenePoint: Point(0, 50), phase: .down, type: .mouse))
        ec.pointerMove(PointerEvent(scenePoint: Point(10, 50), phase: .move, type: .mouse))
        ec.pointerUp(PointerEvent(scenePoint: Point(10, 50), phase: .up, type: .mouse))

        let element = ec.scene.element(id: "img")
        XCTAssertEqual(element?.base.x ?? .nan, 10, accuracy: 1e-9)
        XCTAssertEqual(element?.base.width ?? 0, 90, accuracy: 1e-9)
        guard case let .image(props) = element?.kind, let crop = props.crop else { return XCTFail("crop") }
        // 200px image in 100 units → 2px/unit; 10 units in → crop.x = 20.
        XCTAssertEqual(crop.x, 20, accuracy: 1e-9)
        XCTAssertEqual(crop.width, 180, accuracy: 1e-9)
        XCTAssertTrue(ec.canUndo)
    }

    func testCropDragClampsToImageBounds() {
        let ec = imageEditor()
        ec.beginCropEdit(id: "img", naturalWidth: 200, naturalHeight: 200)
        // Drag the left handle far past the right edge; box stays within image.
        ec.pointerDown(PointerEvent(scenePoint: Point(0, 50), phase: .down, type: .mouse))
        ec.pointerMove(PointerEvent(scenePoint: Point(-100, 50), phase: .move, type: .mouse))
        let element = ec.scene.element(id: "img")
        // Cannot expand beyond the full-image box (left edge clamps at 0).
        XCTAssertGreaterThanOrEqual(element?.base.x ?? -1, 0)
    }

    func testTapAwayFromHandleExitsCrop() {
        let ec = imageEditor()
        ec.beginCropEdit(id: "img", naturalWidth: 200, naturalHeight: 200)
        ec.pointerDown(PointerEvent(scenePoint: Point(500, 500), phase: .down, type: .mouse))
        XCTAssertNil(ec.editingCropID)
    }

    func testSetToolExitsCropMode() {
        let ec = imageEditor()
        ec.beginCropEdit(id: "img", naturalWidth: 200, naturalHeight: 200)
        ec.setTool(.rectangle)
        XCTAssertNil(ec.editingCropID)
    }
}
