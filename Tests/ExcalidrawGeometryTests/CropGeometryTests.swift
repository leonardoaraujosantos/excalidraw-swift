import ExcalidrawModel
import XCTest
@testable import ExcalidrawGeometry

final class CropGeometryTests: XCTestCase {
    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> BoundingBox {
        BoundingBox(minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    func testFullCropCoversNaturalImage() {
        let crop = CropGeometry.fullCrop(naturalWidth: 200, naturalHeight: 100)
        XCTAssertEqual(crop.x, 0)
        XCTAssertEqual(crop.width, 200)
        XCTAssertEqual(crop.height, 100)
        XCTAssertEqual(crop.naturalWidth, 200)
    }

    func testFullImageBoxForUncroppedImage() {
        // 100×100 display shows the whole 200×200 image → 1 scene unit = 2 px.
        let crop = ImageCrop(x: 0, y: 0, width: 200, height: 200, naturalWidth: 200, naturalHeight: 200)
        let full = CropGeometry.fullImageBox(box: box(0, 0, 100, 100), crop: crop)
        XCTAssertEqual(full, box(0, 0, 100, 100))
    }

    func testFullImageBoxForCroppedImage() {
        // Display 100×100 shows crop region 50×50 starting at (25,25) of a
        // 100×100 image → scale 0.5 px/unit. Full image is 200×200 scene units,
        // its top-left offset back by crop origin / scale = 50 units.
        let crop = ImageCrop(x: 25, y: 25, width: 50, height: 50, naturalWidth: 100, naturalHeight: 100)
        let full = CropGeometry.fullImageBox(box: box(0, 0, 100, 100), crop: crop)
        XCTAssertEqual(full.minX, -50, accuracy: 1e-9)
        XCTAssertEqual(full.minY, -50, accuracy: 1e-9)
        XCTAssertEqual(full.width, 200, accuracy: 1e-9)
        XCTAssertEqual(full.height, 200, accuracy: 1e-9)
    }

    func testUpdatedCropTracksDraggedBox() {
        // Whole 200×200 image shown in 100×100 box (2 px/unit). Drag the left
        // edge in by 10 units → crop.x grows by 20 px, width shrinks by 20 px.
        let crop = CropGeometry.fullCrop(naturalWidth: 200, naturalHeight: 200)
        let newCrop = CropGeometry.updatedCrop(box: box(0, 0, 100, 100), crop: crop, newBox: box(10, 0, 90, 100))
        XCTAssertEqual(newCrop.x, 20, accuracy: 1e-9)
        XCTAssertEqual(newCrop.width, 180, accuracy: 1e-9)
        XCTAssertEqual(newCrop.height, 200, accuracy: 1e-9)
        XCTAssertEqual(newCrop.naturalWidth, 200)
    }

    func testClampBoxRestrictsToFullImage() {
        let full = box(0, 0, 100, 100)
        let clamped = CropGeometry.clampBox(box(-20, -20, 200, 200), to: full)
        XCTAssertEqual(clamped, full)
    }
}
