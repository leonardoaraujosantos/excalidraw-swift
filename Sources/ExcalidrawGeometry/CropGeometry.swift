import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Pure geometry for interactive image cropping.
///
/// An image element shows the natural sub-rectangle `crop` (in natural-pixel,
/// top-left coordinates) scaled to fill its display box. Cropping drags a
/// transform handle to shrink (or grow, up to the full image) the display box;
/// the crop rectangle updates so the pixels under the cursor stay put.
public enum CropGeometry {
    /// A fresh crop covering the whole image, used the first time an image is
    /// cropped (when `crop == nil`).
    public static func fullCrop(naturalWidth: Double, naturalHeight: Double) -> ImageCrop {
        ImageCrop(
            x: 0, y: 0, width: naturalWidth, height: naturalHeight,
            naturalWidth: naturalWidth, naturalHeight: naturalHeight
        )
    }

    /// The scene-space box that would display the entire (uncropped) image,
    /// given the current display `box` and its `crop`. This is the limit a crop
    /// handle can be dragged outward to.
    public static func fullImageBox(box: BoundingBox, crop: ImageCrop) -> BoundingBox {
        let sx = crop.width / box.width // natural px per scene unit
        let sy = crop.height / box.height
        let minX = box.minX - crop.x / sx
        let minY = box.minY - crop.y / sy
        let fullWidth = crop.naturalWidth / sx
        let fullHeight = crop.naturalHeight / sy
        return BoundingBox(minX: minX, minY: minY, maxX: minX + fullWidth, maxY: minY + fullHeight)
    }

    /// Clamp a dragged display box to the full-image extent so the crop can
    /// never expose pixels outside the image.
    public static func clampBox(_ box: BoundingBox, to fullBox: BoundingBox) -> BoundingBox {
        BoundingBox(
            minX: max(box.minX, fullBox.minX),
            minY: max(box.minY, fullBox.minY),
            maxX: min(box.maxX, fullBox.maxX),
            maxY: min(box.maxY, fullBox.maxY)
        )
    }

    /// The crop rectangle (natural coords) corresponding to display `newBox`,
    /// given the previous display `box`/`crop`. `newBox` should already be
    /// clamped to `fullImageBox`.
    public static func updatedCrop(box: BoundingBox, crop: ImageCrop, newBox: BoundingBox) -> ImageCrop {
        let sx = crop.width / box.width
        let sy = crop.height / box.height
        var result = crop
        result.x = crop.x + (newBox.minX - box.minX) * sx
        result.y = crop.y + (newBox.minY - box.minY) * sy
        result.width = newBox.width * sx
        result.height = newBox.height * sy
        return result
    }
}
