import { BoundingBox } from "@cyberdynecorp/excalidraw-geometry";
import { Point, normalizeRadians } from "@cyberdynecorp/excalidraw-math";
import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";

/** The resize/rotate handles around a selection's bounding box. */
export type TransformHandle =
  | "topLeft"
  | "top"
  | "topRight"
  | "right"
  | "bottomRight"
  | "bottom"
  | "bottomLeft"
  | "left"
  | "rotation";

const movesLeft = (h: TransformHandle): boolean =>
  h === "topLeft" || h === "left" || h === "bottomLeft";
const movesRight = (h: TransformHandle): boolean =>
  h === "topRight" || h === "right" || h === "bottomRight";
const movesTop = (h: TransformHandle): boolean =>
  h === "topLeft" || h === "top" || h === "topRight";
const movesBottom = (h: TransformHandle): boolean =>
  h === "bottomLeft" || h === "bottom" || h === "bottomRight";

/** Minimum element size in scene units, to avoid collapsing to zero. */
export const MIN_SIZE = 1;

function applyAspect(
  box: BoundingBox,
  original: BoundingBox,
  handle: TransformHandle,
  fromCenter: boolean,
): BoundingBox {
  const ratio = original.width / original.height;
  const scale = Math.max(
    Math.abs(box.width / original.width),
    Math.abs(box.height / original.height),
  );
  const newWidth = original.width * scale;
  const newHeight = newWidth / ratio;

  let { minX, minY, maxX, maxY } = box;
  if (fromCenter) {
    const cx = (original.minX + original.maxX) / 2;
    const cy = (original.minY + original.maxY) / 2;
    minX = cx - newWidth / 2;
    maxX = cx + newWidth / 2;
    minY = cy - newHeight / 2;
    maxY = cy + newHeight / 2;
  } else {
    if (movesRight(handle)) maxX = minX + newWidth;
    else minX = maxX - newWidth;
    if (movesBottom(handle)) maxY = minY + newHeight;
    else minY = maxY - newHeight;
  }
  return new BoundingBox(minX, minY, maxX, maxY);
}

function clampMinSize(box: BoundingBox): BoundingBox {
  const result = new BoundingBox(box.minX, box.minY, box.maxX, box.maxY);
  if (result.width < MIN_SIZE) result.maxX = result.minX + MIN_SIZE;
  if (result.height < MIN_SIZE) result.maxY = result.minY + MIN_SIZE;
  return result;
}

export const Transform = {
  /** Scene-space positions of every handle around `bounds`. */
  handlePositions(bounds: BoundingBox, rotationOffset: number): Map<TransformHandle, Point> {
    const midX = (bounds.minX + bounds.maxX) / 2;
    const midY = (bounds.minY + bounds.maxY) / 2;
    return new Map<TransformHandle, Point>([
      ["topLeft", new Point(bounds.minX, bounds.minY)],
      ["top", new Point(midX, bounds.minY)],
      ["topRight", new Point(bounds.maxX, bounds.minY)],
      ["right", new Point(bounds.maxX, midY)],
      ["bottomRight", new Point(bounds.maxX, bounds.maxY)],
      ["bottom", new Point(midX, bounds.maxY)],
      ["bottomLeft", new Point(bounds.minX, bounds.maxY)],
      ["left", new Point(bounds.minX, midY)],
      ["rotation", new Point(midX, bounds.minY - rotationOffset)],
    ]);
  },

  /** New bounds after dragging `handle` to `pointer`. */
  resize(
    bounds: BoundingBox,
    handle: TransformHandle,
    pointer: Point,
    keepAspect = false,
    fromCenter = false,
  ): BoundingBox {
    let minX = bounds.minX;
    let minY = bounds.minY;
    let maxX = bounds.maxX;
    let maxY = bounds.maxY;
    const centerX = (minX + maxX) / 2;
    const centerY = (minY + maxY) / 2;

    if (movesLeft(handle)) minX = pointer.x;
    if (movesRight(handle)) maxX = pointer.x;
    if (movesTop(handle)) minY = pointer.y;
    if (movesBottom(handle)) maxY = pointer.y;

    if (fromCenter) {
      if (movesLeft(handle)) maxX = 2 * centerX - minX;
      if (movesRight(handle)) minX = 2 * centerX - maxX;
      if (movesTop(handle)) maxY = 2 * centerY - minY;
      if (movesBottom(handle)) minY = 2 * centerY - maxY;
    }

    let result = new BoundingBox(
      Math.min(minX, maxX),
      Math.min(minY, maxY),
      Math.max(minX, maxX),
      Math.max(minY, maxY),
    );
    if (keepAspect && bounds.width !== 0 && bounds.height !== 0) {
      result = applyAspect(result, bounds, handle, fromCenter);
    }
    return clampMinSize(result);
  },

  /** Map an element from `old` bounds into `next` bounds, scaling proportionally. */
  scale(el: ExcalidrawElement, old: BoundingBox, next: BoundingBox): ExcalidrawElement {
    const sx = old.width === 0 ? 1 : next.width / old.width;
    const sy = old.height === 0 ? 1 : next.height / old.height;
    const e: ExcalidrawElement = {
      ...el,
      x: next.minX + (el.x - old.minX) * sx,
      y: next.minY + (el.y - old.minY) * sy,
      width: el.width * sx,
      height: el.height * sy,
    };
    if (e.type === "line" || e.type === "arrow" || e.type === "freedraw") {
      e.points = e.points.map((p) => [p[0] * sx, p[1] * sy]);
    } else if (e.type === "text") {
      e.fontSize *= Math.abs(sy);
    }
    return e;
  },

  /** Translate an element by `(dx, dy)`. */
  translate(el: ExcalidrawElement, dx: number, dy: number): ExcalidrawElement {
    return { ...el, x: el.x + dx, y: el.y + dy };
  },

  /** Rotation angle (radians) for a rotation-handle drag; `snap` constrains to 15°. */
  rotationAngle(center: Point, pointer: Point, snap: boolean): number {
    let angle = normalizeRadians(
      Math.atan2(pointer.y - center.y, pointer.x - center.x) + Math.PI / 2,
    );
    if (snap) {
      const step = Math.PI / 12;
      angle = Math.round(angle / step) * step;
    }
    return angle;
  },

  movesLeft,
  movesRight,
  movesTop,
  movesBottom,
} as const;
