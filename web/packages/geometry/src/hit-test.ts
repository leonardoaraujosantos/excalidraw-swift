import { Ellipse, LineSegment, PRECISION, Point, Polygon } from "@cyberdynecorp/excalidraw-math";
import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";
import type { BoundingBox } from "./bounding-box.js";
import { absoluteCoords, bounds, isPathALoop, unrotatedOutline } from "./element-geometry.js";

function isTransparent(color: string): boolean {
  if (color === "transparent" || color.length === 0) return true;
  return color.length === 9 && color.startsWith("#") && color.endsWith("00");
}

function hasBackground(type: ExcalidrawElement["type"]): boolean {
  switch (type) {
    case "rectangle":
    case "iframe":
    case "embeddable":
    case "ellipse":
    case "diamond":
    case "line":
    case "freedraw":
      return true;
    default:
      return false;
  }
}

function hasBoundText(el: ExcalidrawElement): boolean {
  return el.boundElements?.some((b) => b.type === "text") ?? false;
}

/** Whether the element should be hit "from the inside" (`shouldTestInside`). */
export function shouldTestInside(el: ExcalidrawElement): boolean {
  if (el.type === "arrow") return false;
  const draggableFromInside =
    (hasBackground(el.type) && !isTransparent(el.backgroundColor)) ||
    hasBoundText(el) ||
    el.type === "iframe" ||
    el.type === "embeddable" ||
    el.type === "text";

  if (el.type === "line" || el.type === "freedraw") {
    return draggableFromInside && isPathALoop(el.points);
  }
  if (el.type === "image") return true;
  return draggableFromInside;
}

function rotatedSegments(el: ExcalidrawElement, center: Point): LineSegment[] {
  const outline = unrotatedOutline(el);
  const pts = outline.points.map((p) => p.rotated(center, el.angle));
  if (pts.length < 2) return [];
  const segments: LineSegment[] = [];
  for (let i = 0; i < pts.length - 1; i++) segments.push(new LineSegment(pts[i]!, pts[i + 1]!));
  const first = pts[0]!;
  const last = pts[pts.length - 1]!;
  if (outline.closed && !first.equals(last)) segments.push(new LineSegment(last, first));
  return segments;
}

function isPointInRotatedBounds(
  point: Point,
  box: BoundingBox,
  angle: number,
  tolerance: number,
): boolean {
  const center = new Point((box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2);
  const adjusted = angle === 0 ? point : point.rotated(center, -angle);
  return adjusted.isWithin(
    new Point(box.minX - tolerance, box.minY - tolerance),
    new Point(box.maxX + tolerance, box.maxY + tolerance),
  );
}

/** Strict interior test (`isPointInElement`). Open paths have no interior. */
export function isPointInside(el: ExcalidrawElement, point: Point): boolean {
  const { x1, y1, x2, y2, cx, cy } = absoluteCoords(el);
  const center = new Point(cx, cy);
  if (el.type === "ellipse") {
    const local = point.rotated(center, -el.angle);
    return new Ellipse(center, (x2 - x1) / 2, (y2 - y1) / 2).includes(local);
  }
  const outline = unrotatedOutline(el);
  if (!outline.closed || outline.points.length < 3) return false;
  const rotated = outline.points.map((p) => p.rotated(center, el.angle));
  return new Polygon(rotated).includes(point);
}

/** Shortest distance from `point` to the element outline (`distanceToElement`). */
export function distanceToElement(el: ExcalidrawElement, point: Point): number {
  const { x1, y1, x2, y2, cx, cy } = absoluteCoords(el);
  const center = new Point(cx, cy);
  if (el.type === "ellipse") {
    const local = point.rotated(center, -el.angle);
    return new Ellipse(center, (x2 - x1) / 2, (y2 - y1) / 2).distance(local);
  }
  const segments = rotatedSegments(el, center);
  const first = segments[0];
  if (first === undefined) {
    const outline = unrotatedOutline(el);
    const p0 = outline.points[0];
    return p0 !== undefined
      ? p0.rotated(center, el.angle).distance(point)
      : Math.min(Math.abs(point.x - x1), Math.abs(point.y - y1));
  }
  let min = first.distanceToPoint(point);
  for (let i = 1; i < segments.length; i++) {
    min = Math.min(min, segments[i]!.distanceToPoint(point));
  }
  return min;
}

/** Whether `point` lies on the element outline within `threshold`. */
export function isPointOnOutline(el: ExcalidrawElement, point: Point, threshold: number): boolean {
  return distanceToElement(el, point) <= Math.max(threshold, PRECISION);
}

/** Whether `point` (scene coords) hits the element within `threshold` (`hitElementItself`). */
export function hit(el: ExcalidrawElement, point: Point, threshold: number): boolean {
  const nonRotated = bounds(el, true);
  if (!isPointInRotatedBounds(point, nonRotated, el.angle, threshold)) return false;
  if (shouldTestInside(el)) {
    return isPointInside(el, point) || isPointOnOutline(el, point, threshold);
  }
  return isPointOnOutline(el, point, threshold);
}
