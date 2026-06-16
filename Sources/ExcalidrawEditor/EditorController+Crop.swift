import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Interactive image cropping: a dedicated edit mode entered (e.g. on a
/// double-tap of an image) that drags the eight box handles to reframe which
/// part of the natural image is shown. Split out of `EditorController` to keep
/// that type focused on the core pointer state machine.
public extension EditorController {
    /// Enter crop mode for image `id`. The UI supplies the natural pixel size
    /// (from decoding the image). Returns false if `id` is not an image.
    @discardableResult
    func beginCropEdit(id: String, naturalWidth: Double, naturalHeight: Double) -> Bool {
        guard let element = scene.element(id: id), case .image = element.kind,
              naturalWidth > 0, naturalHeight > 0 else { return false }
        editingCropID = id
        cropNaturalSize = (naturalWidth, naturalHeight)
        selectedIDs = [id]
        return true
    }

    func exitCropEdit() {
        editingCropID = nil
        cropNaturalSize = nil
        cropDrag = nil
    }

    /// The topmost image element hit at `point`, with the data URL the UI needs
    /// to decode its natural size. Used to enter crop mode (e.g. on double-tap).
    func imageHit(at point: Point) -> (id: String, dataURL: String)? {
        let threshold = handleHitRadius(.mouse)
        for element in scene.visibleElements.reversed() where !element.base.locked {
            guard case let .image(props) = element.kind, let fileId = props.fileId,
                  let file = scene.files[fileId], HitTest.hit(element, at: point, threshold: threshold)
            else { continue }
            return (element.id, file.dataURL)
        }
        return nil
    }

    /// The eight handle positions (scene coords) framing the image being
    /// cropped, for the overlay. `nil` when not cropping.
    func cropEditHandles() -> [Point]? {
        guard let frame = cropFrame() else { return nil }
        return Transform.handlePositions(for: frame, rotationOffset: 0)
            .filter { $0.key != .rotation }
            .map(\.value)
    }

    /// The current display box of the image being cropped.
    func cropFrame() -> BoundingBox? {
        guard let id = editingCropID, let element = scene.element(id: id) else { return nil }
        let b = element.base
        return BoundingBox(minX: b.x, minY: b.y, maxX: b.x + b.width, maxY: b.y + b.height)
    }

    // MARK: Internal drag handling

    /// The crop in effect for the element (its stored crop, or a full crop when
    /// none has been set yet).
    internal func effectiveCrop(_ element: ExcalidrawElement) -> ImageCrop? {
        guard case let .image(props) = element.kind else { return nil }
        if let crop = props.crop { return crop }
        guard let natural = cropNaturalSize else { return nil }
        return CropGeometry.fullCrop(naturalWidth: natural.width, naturalHeight: natural.height)
    }

    internal func handleCropEditDown(_ event: PointerEvent) -> Bool {
        guard let id = editingCropID, let element = scene.element(id: id),
              let frame = cropFrame(), let crop = effectiveCrop(element) else {
            exitCropEdit()
            return false
        }
        let threshold = handleHitRadius(event.type)
        let handles = Transform.handlePositions(for: frame, rotationOffset: 0)
            .filter { $0.key != .rotation }
        for (handle, position) in handles where position.distance(to: event.scenePoint) <= threshold {
            cropDrag = CropDrag(
                handle: handle, startBox: frame, startCrop: crop,
                fullBox: CropGeometry.fullImageBox(box: frame, crop: crop)
            )
            return true
        }
        // Tapped away from any handle — leave crop mode.
        exitCropEdit()
        return false
    }

    internal func moveCropDrag(to point: Point) {
        guard let drag = cropDrag, let id = editingCropID, let element = scene.element(id: id),
              case var .image(props) = element.kind else { return }
        let resized = Transform.resize(drag.startBox, handle: drag.handle, to: point)
        let newBox = CropGeometry.clampBox(resized, to: drag.fullBox)
        props.crop = CropGeometry.updatedCrop(box: drag.startBox, crop: drag.startCrop, newBox: newBox)
        var updated = element
        updated.kind = .image(props)
        updated.base.x = newBox.minX
        updated.base.y = newBox.minY
        updated.base.width = newBox.width
        updated.base.height = newBox.height
        store.modifyScene { $0.replace(updated) }
    }
}
