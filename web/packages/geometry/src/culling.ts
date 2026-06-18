import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";
import { BoundingBox } from "./bounding-box.js";
import { bounds } from "./element-geometry.js";

function intersects(a: BoundingBox, b: BoundingBox): boolean {
  return a.minX <= b.maxX && a.maxX >= b.minX && a.minY <= b.maxY && a.maxY >= b.minY;
}

/**
 * Viewport culling: the elements that intersect `visible`, expanded by `margin`
 * scene units so wide strokes near the edge aren't clipped. (parity: Culling.swift)
 */
export function cullVisible(
  elements: ExcalidrawElement[],
  visible: BoundingBox,
  margin = 0,
): ExcalidrawElement[] {
  const region = new BoundingBox(
    visible.minX - margin,
    visible.minY - margin,
    visible.maxX + margin,
    visible.maxY + margin,
  );
  return elements.filter((el) => intersects(bounds(el), region));
}
