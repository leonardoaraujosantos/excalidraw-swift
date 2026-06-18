import { Point } from "@cyberdynecorp/excalidraw-math";
import type { BoundingBox } from "./bounding-box.js";

function ellipseParams(box: BoundingBox): { cx: number; cy: number; rx: number; ry: number } {
  return {
    cx: (box.minX + box.maxX) / 2,
    cy: (box.minY + box.maxY) / 2,
    rx: box.width / 2,
    ry: box.height / 2,
  };
}

/** Normalize raw `(x, y)` samples to [0, 1] then map onto `box`. */
function fit(raw: [number, number][], box: BoundingBox): Point[] {
  const xs = raw.map((p) => p[0]);
  const ys = raw.map((p) => p[1]);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  const spanX = Math.max(maxX - minX, 1e-9);
  const spanY = Math.max(maxY - minY, 1e-9);
  return raw.map(
    ([x, y]) =>
      new Point(
        box.minX + ((x - minX) / spanX) * box.width,
        box.minY + ((y - minY) / spanY) * box.height,
      ),
  );
}

/**
 * Generates the vertex set of a clean shape fitted to a bounding box — the
 * "perfect" output when a freehand stroke is snapped. (parity: ShapeGenerator.swift)
 */
export const ShapeGenerator = {
  /** A regular `sides`-gon inscribed in `box`, first vertex at the top. */
  regularPolygon(sides: number, box: BoundingBox): Point[] {
    const { cx, cy, rx, ry } = ellipseParams(box);
    const n = Math.max(sides, 3);
    const result: Point[] = [];
    for (let i = 0; i < n; i++) {
      const a = -Math.PI / 2 + (2 * Math.PI * i) / sides;
      result.push(new Point(cx + rx * Math.cos(a), cy + ry * Math.sin(a)));
    }
    return result;
  },

  /** An `points`-pointed star inscribed in `box`, first tip at the top. */
  star(box: BoundingBox, points = 5, innerRatio = 0.42): Point[] {
    const { cx, cy, rx, ry } = ellipseParams(box);
    const count = Math.max(points, 3) * 2;
    const result: Point[] = [];
    for (let i = 0; i < count; i++) {
      const a = -Math.PI / 2 + (Math.PI * i) / points;
      const r = i % 2 === 0 ? 1 : innerRatio;
      result.push(new Point(cx + rx * r * Math.cos(a), cy + ry * r * Math.sin(a)));
    }
    return result;
  },

  /** A heart fitted to `box` (classic parametric heart). */
  heart(box: BoundingBox, samples = 48): Point[] {
    const raw: [number, number][] = [];
    for (let i = 0; i < samples; i++) {
      const t = (2 * Math.PI * i) / samples;
      const x = 16 * Math.sin(t) ** 3;
      const y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
      raw.push([x, y]);
    }
    return fit(raw, box);
  },

  /** A puffy cloud fitted to `box` — a bumpy closed curve with `lobes` lobes. */
  cloud(box: BoundingBox, lobes = 9, samples = 72): Point[] {
    const { cx, cy, rx, ry } = ellipseParams(box);
    const result: Point[] = [];
    for (let i = 0; i < samples; i++) {
      const a = (2 * Math.PI * i) / samples;
      const r = 0.82 + 0.18 * Math.abs(Math.sin((lobes * a) / 2));
      result.push(new Point(cx + rx * r * Math.cos(a), cy + ry * r * Math.sin(a)));
    }
    return result;
  },

  /** A speech bubble fitted to `box`: rounded body with a triangular tail. */
  speechBubble(box: BoundingBox): Point[] {
    const w = box.width;
    const h = box.height;
    const bodyBottom = box.minY + h * 0.72;
    const r = Math.min(w, h) * 0.18;
    const left = box.minX;
    const right = box.maxX;
    const top = box.minY;
    const pts: Point[] = [];
    const arc = (cxx: number, cyy: number, from: number, to: number): void => {
      for (let k = 0; k <= 4; k++) {
        const a = from + ((to - from) * k) / 4;
        pts.push(new Point(cxx + r * Math.cos(a), cyy + r * Math.sin(a)));
      }
    };
    arc(left + r, top + r, Math.PI, 1.5 * Math.PI);
    arc(right - r, top + r, 1.5 * Math.PI, 2 * Math.PI);
    arc(right - r, bodyBottom - r, 0, 0.5 * Math.PI);
    pts.push(new Point(left + w * 0.42, bodyBottom));
    pts.push(new Point(left + w * 0.28, box.maxY));
    pts.push(new Point(left + w * 0.3, bodyBottom));
    arc(left + r, bodyBottom - r, 0.5 * Math.PI, Math.PI);
    return pts;
  },
} as const;
