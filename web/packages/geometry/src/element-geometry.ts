import { Point } from "@cyberdynecorp/excalidraw-math";
import type { ExcalidrawElement, LocalPoint } from "@cyberdynecorp/excalidraw-model";
import { BoundingBox } from "./bounding-box.js";

export const LINE_CONFIRM_THRESHOLD = 40;

type PolylineElement = Extract<ExcalidrawElement, { type: "freedraw" | "line" | "arrow" }>;

function isPolyline(el: ExcalidrawElement): el is PolylineElement {
  return el.type === "freedraw" || el.type === "line" || el.type === "arrow";
}

/** Scene-space points for polyline elements (freedraw/line/arrow), else null. */
export function scenePoints(el: ExcalidrawElement): Point[] | null {
  if (!isPolyline(el)) return null;
  return el.points.map((p: LocalPoint) => new Point(el.x + p[0], el.y + p[1]));
}

/** Whether a path of relative points is closed (`isPathALoop`). */
export function isPathALoop(points: LocalPoint[]): boolean {
  if (points.length < 3) return false;
  const first = points[0]!;
  const last = points[points.length - 1]!;
  return (
    new Point(first[0], first[1]).distance(new Point(last[0], last[1])) <= LINE_CONFIRM_THRESHOLD
  );
}

export interface AbsoluteCoords {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  cx: number;
  cy: number;
}

/** `[x1, y1, x2, y2, cx, cy]` in scene coordinates (`getElementAbsoluteCoords`). */
export function absoluteCoords(el: ExcalidrawElement): AbsoluteCoords {
  const pts = scenePoints(el);
  if (pts !== null && pts.length > 0) {
    const box = BoundingBox.fromPoints(pts)!;
    return {
      x1: box.minX,
      y1: box.minY,
      x2: box.maxX,
      y2: box.maxY,
      cx: (box.minX + box.maxX) / 2,
      cy: (box.minY + box.maxY) / 2,
    };
  }
  const x1 = el.x;
  const y1 = el.y;
  const x2 = el.x + el.width;
  const y2 = el.y + el.height;
  return { x1, y1, x2, y2, cx: (x1 + x2) / 2, cy: (y1 + y2) / 2 };
}

export interface Outline {
  points: Point[];
  closed: boolean;
}

/** An element's outline as unrotated scene-space vertices, plus closed flag. */
export function unrotatedOutline(el: ExcalidrawElement): Outline {
  const x1 = el.x;
  const y1 = el.y;
  const x2 = el.x + el.width;
  const y2 = el.y + el.height;
  const cx = (x1 + x2) / 2;
  const cy = (y1 + y2) / 2;

  switch (el.type) {
    case "diamond":
      return {
        points: [new Point(cx, y1), new Point(x2, cy), new Point(cx, y2), new Point(x1, cy)],
        closed: true,
      };
    case "line":
      return {
        points: el.points.map((p) => new Point(el.x + p[0], el.y + p[1])),
        closed: el.polygon || isPathALoop(el.points),
      };
    case "arrow":
      return { points: scenePoints(el) ?? [], closed: false };
    case "freedraw":
      return {
        points: el.points.map((p) => new Point(el.x + p[0], el.y + p[1])),
        closed: isPathALoop(el.points),
      };
    default:
      return {
        points: [new Point(x1, y1), new Point(x2, y1), new Point(x2, y2), new Point(x1, y2)],
        closed: true,
      };
  }
}

/** Bounding box of the element; when `nonRotated` is true its rotation is ignored. */
export function bounds(el: ExcalidrawElement, nonRotated = false): BoundingBox {
  const { x1, y1, x2, y2, cx, cy } = absoluteCoords(el);
  if (nonRotated || el.angle === 0) {
    return new BoundingBox(x1, y1, x2, y2);
  }
  const angle = el.angle;
  const center = new Point(cx, cy);
  const fallback = new BoundingBox(x1, y1, x2, y2);

  if (el.type === "freedraw" || el.type === "line" || el.type === "arrow") {
    const rotated = (scenePoints(el) ?? []).map((p) => p.rotated(center, angle));
    return BoundingBox.fromPoints(rotated) ?? fallback;
  }
  if (el.type === "ellipse") {
    const w = (x2 - x1) / 2;
    const h = (y2 - y1) / 2;
    const ww = Math.hypot(w * Math.cos(angle), h * Math.sin(angle));
    const hh = Math.hypot(h * Math.cos(angle), w * Math.sin(angle));
    return new BoundingBox(cx - ww, cy - hh, cx + ww, cy + hh);
  }
  const corners = unrotatedOutline(el).points.map((p) => p.rotated(center, angle));
  return BoundingBox.fromPoints(corners) ?? fallback;
}

/** Combined bounds of several elements (`getCommonBounds`); null if empty. */
export function commonBounds(elements: ExcalidrawElement[]): BoundingBox | null {
  let acc: BoundingBox | null = null;
  for (const el of elements) {
    const b = bounds(el);
    acc = acc === null ? b : acc.union(b);
  }
  return acc;
}
