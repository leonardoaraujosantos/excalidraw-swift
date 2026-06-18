import { Point } from "@cyberdynecorp/excalidraw-math";
import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";
import { BoundingBox } from "./bounding-box.js";
import { bounds } from "./element-geometry.js";

/** Default search distance around an element's bounds, in scene units. */
export const BINDING_DISTANCE = 16;

export function isBindable(el: ExcalidrawElement): boolean {
  switch (el.type) {
    case "rectangle":
    case "diamond":
    case "ellipse":
    case "text":
    case "image":
    case "frame":
    case "magicframe":
    case "embeddable":
    case "iframe":
      return true;
    default:
      return false;
  }
}

/**
 * The smallest bindable element whose bounds (expanded by `threshold`) contains
 * `point`, excluding `excluding`. (parity: Binding.swift)
 */
export function bindableElementAt(
  point: Point,
  elements: ExcalidrawElement[],
  excluding: Set<string>,
  threshold = BINDING_DISTANCE,
): ExcalidrawElement | null {
  let best: { element: ExcalidrawElement; area: number } | null = null;
  for (const el of elements) {
    if (!isBindable(el) || excluding.has(el.id)) continue;
    const b = bounds(el);
    const expanded = new BoundingBox(
      b.minX - threshold,
      b.minY - threshold,
      b.maxX + threshold,
      b.maxY + threshold,
    );
    if (expanded.contains(point)) {
      const area = b.width * b.height;
      if (best === null || area < best.area) best = { element: el, area };
    }
  }
  return best?.element ?? null;
}

/** Ratio (0–1 on each axis) of `point` within `bounds`. */
export function fixedPointFor(point: Point, box: BoundingBox): Point {
  return new Point(
    box.width === 0 ? 0.5 : (point.x - box.minX) / box.width,
    box.height === 0 ? 0.5 : (point.y - box.minY) / box.height,
  );
}

/** The scene point for a fixed-point ratio within `bounds`. */
export function pointForFixedPoint(fixed: Point, box: BoundingBox): Point {
  return new Point(box.minX + fixed.x * box.width, box.minY + fixed.y * box.height);
}
