import { Point } from "@cyberdynecorp/excalidraw-math";
import { BoundingBox } from "./bounding-box.js";
import { ShapeGenerator } from "./shape-generator.js";

/** A shape a freehand stroke can be snapped to. */
export type RecognizedShape =
  | "line"
  | "rectangle"
  | "diamond"
  | "ellipse"
  | "triangle"
  | "pentagon"
  | "hexagon"
  | "star"
  | "heart"
  | "cloud"
  | "speechBubble";

/** Shapes built as a closed polygon-line (everything except box/ellipse/line). */
export function isPolylineShape(shape: RecognizedShape): boolean {
  return shape !== "line" && shape !== "rectangle" && shape !== "diamond" && shape !== "ellipse";
}

export interface ShapeRecognition {
  shape: RecognizedShape;
  bounds: BoundingBox;
  vertices: Point[];
}

function centroid(points: Point[]): Point {
  const n = Math.max(points.length, 1);
  let sx = 0;
  let sy = 0;
  for (const p of points) {
    sx += p.x;
    sy += p.y;
  }
  return new Point(sx / n, sy / n);
}

function circularity(points: Point[]): number {
  const c = centroid(points);
  const radii = points.map((p) => p.distance(c));
  const mean = radii.reduce((a, b) => a + b, 0) / radii.length;
  if (mean <= 0) return Number.POSITIVE_INFINITY;
  const variance = radii.reduce((a, r) => a + (r - mean) * (r - mean), 0) / radii.length;
  return Math.sqrt(variance) / mean;
}

function perpendicularDistance(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) return p.distance(a);
  const t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared;
  return p.distance(new Point(a.x + t * dx, a.y + t * dy));
}

function rdp(points: Point[], epsilon: number): Point[] {
  if (points.length < 3) return points;
  const first = points[0]!;
  const last = points[points.length - 1]!;
  let maxDistance = 0;
  let index = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = perpendicularDistance(points[i]!, first, last);
    if (d > maxDistance) {
      maxDistance = d;
      index = i;
    }
  }
  if (maxDistance > epsilon) {
    const left = rdp(points.slice(0, index + 1), epsilon);
    const right = rdp(points.slice(index), epsilon);
    return [...left.slice(0, -1), ...right];
  }
  return [first, last];
}

function removeCollinear(points: Point[], epsilon: number): Point[] {
  if (points.length <= 2) return points;
  const result = [points[0]!];
  for (let i = 1; i < points.length - 1; i++) {
    if (perpendicularDistance(points[i]!, result[result.length - 1]!, points[i + 1]!) > epsilon) {
      result.push(points[i]!);
    }
  }
  result.push(points[points.length - 1]!);
  return result;
}

function rectangleOrDiamond(vertices: Point[], box: BoundingBox): RecognizedShape {
  const midX = (box.minX + box.maxX) / 2;
  const midY = (box.minY + box.maxY) / 2;
  const boxCorners = [
    new Point(box.minX, box.minY),
    new Point(box.maxX, box.minY),
    new Point(box.maxX, box.maxY),
    new Point(box.minX, box.maxY),
  ];
  const edgeMids = [
    new Point(midX, box.minY),
    new Point(box.maxX, midY),
    new Point(midX, box.maxY),
    new Point(box.minX, midY),
  ];
  const score = (targets: Point[]): number =>
    vertices
      .slice(0, 4)
      .reduce((sum, v) => sum + Math.min(...targets.map((t) => v.distance(t))), 0);
  return score(boxCorners) <= score(edgeMids) ? "rectangle" : "diamond";
}

function detectStar(simplified: Point[]): boolean {
  const vertices = simplified.slice(0, -1);
  if (vertices.length < 8 || vertices.length > 14) return false;
  const c = centroid(vertices);
  const radii = vertices.map((v) => v.distance(c));
  const mean = radii.reduce((a, b) => a + b, 0) / radii.length;
  if (mean <= 0) return false;
  if (Math.min(...radii) / Math.max(...radii) >= 0.7) return false;
  let alternations = 0;
  for (let i = 0; i < radii.length; i++) {
    const a = radii[i]! - mean;
    const b = radii[(i + 1) % radii.length]! - mean;
    if (a * b < 0) alternations++;
  }
  return alternations >= 8;
}

function detectHeart(points: Point[], box: BoundingBox): boolean {
  const cx = (box.minX + box.maxX) / 2;
  const topOf = (xs: Point[]): number | null =>
    xs.length === 0 ? null : Math.min(...xs.map((p) => p.y));
  const lt = topOf(points.filter((p) => p.x < cx - box.width * 0.1));
  const rt = topOf(points.filter((p) => p.x > cx + box.width * 0.1));
  const ct = topOf(points.filter((p) => Math.abs(p.x - cx) < box.width * 0.1));
  if (lt === null || rt === null || ct === null) return false;
  const notch = ct - Math.min(lt, rt) > box.height * 0.05;
  const bottom = points.reduce((a, b) => (b.y > a.y ? b : a));
  const pointed = Math.abs(bottom.x - cx) < box.width * 0.2;
  return notch && pointed;
}

function detectCloud(points: Point[]): boolean {
  const c = centroid(points);
  const radii = points.map((p) => p.distance(c));
  const maxR = Math.max(...radii);
  const minR = Math.min(...radii);
  if (maxR <= 0) return false;
  const depth = 1 - minR / maxR;
  if (depth <= 0.08 || depth >= 0.45) return false;
  let bumps = 0;
  const n = radii.length;
  for (let i = 0; i < n; i++) {
    const prev = radii[(i - 1 + n) % n]!;
    const cur = radii[i]!;
    const next = radii[(i + 1) % n]!;
    if (cur >= prev && cur > next) bumps++;
  }
  return bumps >= 7;
}

function detectSpeechBubble(points: Point[], box: BoundingBox): boolean {
  if (box.width <= 0 || box.height <= 0) return false;
  const top = points.filter((p) => p.y < box.minY + box.height * 0.3);
  const bottom = points.filter((p) => p.y > box.minY + box.height * 0.8);
  if (top.length === 0 || bottom.length === 0) return false;
  const span = (xs: Point[]): number =>
    Math.max(...xs.map((p) => p.x)) - Math.min(...xs.map((p) => p.x));
  return span(top) > box.width * 0.7 && span(bottom) < box.width * 0.5;
}

/** Recognizes a freehand stroke as a clean shape. (parity: ShapeRecognizer.swift) */
export const ShapeRecognizer = {
  recognize(points: Point[]): ShapeRecognition | null {
    const box = BoundingBox.fromPoints(points);
    if (points.length < 2 || box === null) return null;
    const diagonal = Math.sqrt(box.width * box.width + box.height * box.height);
    if (diagonal <= 1) return null;

    const first = points[0]!;
    const last = points[points.length - 1]!;
    const closed = points.length >= 3 && first.distance(last) < diagonal * 0.25;
    const epsilon = diagonal * 0.08;
    const simplified = removeCollinear(rdp(points, epsilon), epsilon);

    if (!closed) {
      return simplified.length <= 2
        ? { shape: "line", bounds: box, vertices: [first, last] }
        : null;
    }

    if (detectStar(simplified))
      return { shape: "star", bounds: box, vertices: ShapeGenerator.star(box, 5) };
    if (detectHeart(points, box))
      return { shape: "heart", bounds: box, vertices: ShapeGenerator.heart(box) };
    if (detectCloud(points))
      return { shape: "cloud", bounds: box, vertices: ShapeGenerator.cloud(box) };
    if (detectSpeechBubble(points, box)) {
      return { shape: "speechBubble", bounds: box, vertices: ShapeGenerator.speechBubble(box) };
    }

    if (circularity(points) < 0.035) return { shape: "ellipse", bounds: box, vertices: [] };

    const corners = Math.max(simplified.length - 1, 0);
    switch (corners) {
      case 3:
        return { shape: "triangle", bounds: box, vertices: simplified.slice(0, 3) };
      case 4:
        return { shape: rectangleOrDiamond(simplified, box), bounds: box, vertices: [] };
      case 5:
        return { shape: "pentagon", bounds: box, vertices: ShapeGenerator.regularPolygon(5, box) };
      case 6:
        return { shape: "hexagon", bounds: box, vertices: ShapeGenerator.regularPolygon(6, box) };
      default:
        return { shape: "ellipse", bounds: box, vertices: [] };
    }
  },
} as const;
