import type { ImageCrop } from "@xs/model";
import { BoundingBox } from "./bounding-box.js";

/**
 * Pure geometry for interactive image cropping. An image shows the natural
 * sub-rectangle `crop` scaled to fill its display box; dragging a handle shrinks
 * or grows the display box (up to the full image) and the crop updates so the
 * pixels under the cursor stay put. (parity: CropGeometry.swift)
 */
export const CropGeometry = {
  /** A fresh crop covering the whole image (used when `crop == null`). */
  fullCrop(naturalWidth: number, naturalHeight: number): ImageCrop {
    return { x: 0, y: 0, width: naturalWidth, height: naturalHeight, naturalWidth, naturalHeight };
  },

  /** The scene-space box that would display the entire (uncropped) image. */
  fullImageBox(box: BoundingBox, crop: ImageCrop): BoundingBox {
    const sx = crop.width / box.width;
    const sy = crop.height / box.height;
    const minX = box.minX - crop.x / sx;
    const minY = box.minY - crop.y / sy;
    return new BoundingBox(
      minX,
      minY,
      minX + crop.naturalWidth / sx,
      minY + crop.naturalHeight / sy,
    );
  },

  /** Clamp a dragged display box to the full-image extent. */
  clampBox(box: BoundingBox, fullBox: BoundingBox): BoundingBox {
    return new BoundingBox(
      Math.max(box.minX, fullBox.minX),
      Math.max(box.minY, fullBox.minY),
      Math.min(box.maxX, fullBox.maxX),
      Math.min(box.maxY, fullBox.maxY),
    );
  },

  /** The crop (natural coords) corresponding to display `newBox`. */
  updatedCrop(box: BoundingBox, crop: ImageCrop, newBox: BoundingBox): ImageCrop {
    const sx = crop.width / box.width;
    const sy = crop.height / box.height;
    return {
      ...crop,
      x: crop.x + (newBox.minX - box.minX) * sx,
      y: crop.y + (newBox.minY - box.minY) * sy,
      width: newBox.width * sx,
      height: newBox.height * sy,
    };
  },
} as const;
