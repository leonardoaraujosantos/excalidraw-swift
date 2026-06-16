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
}
