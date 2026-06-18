import type { ExcalidrawElement, LocalPoint } from "@cyberdynecorp/excalidraw-model";
import rough from "roughjs";
import type { Drawable, Options } from "roughjs/bin/core";

const generator = rough.generator();

function isLoop(points: LocalPoint[]): boolean {
  if (points.length < 3) return false;
  const first = points[0]!;
  const last = points[points.length - 1]!;
  return Math.hypot(first[0] - last[0], first[1] - last[1]) <= 40;
}

/**
 * Closed outline of a rounded rectangle (`w × h`), each corner sampled as a
 * quarter-arc, for the hand-drawn rounded look. (parity: ElementDrawable.swift)
 */
export function roundedRectanglePoints(w: number, h: number, samples = 6): LocalPoint[] {
  const r = Math.min(Math.min(w, h) / 4, 32);
  if (r <= 0) {
    return [
      [0, 0],
      [w, 0],
      [w, h],
      [0, h],
    ];
  }
  const corners: [number, number, number][] = [
    [r, r, Math.PI],
    [w - r, r, 1.5 * Math.PI],
    [w - r, h - r, 0],
    [r, h - r, 0.5 * Math.PI],
  ];
  const points: LocalPoint[] = [];
  for (const [cx, cy, start] of corners) {
    for (let k = 0; k <= samples; k++) {
      const a = start + ((Math.PI / 2) * k) / samples;
      points.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
  }
  return points;
}

function linearDrawable(
  points: LocalPoint[],
  closed: boolean,
  rounded: boolean,
  o: Options,
): Drawable | null {
  if (points.length < 2) return null;
  if (rounded && points.length > 2) return generator.curve(points, o);
  return closed ? generator.polygon(points, o) : generator.linearPath(points, o);
}

/**
 * Generate the rough.js `Drawable` for an element, in element-local coordinates
 * (origin at the element's `x, y`). (parity: ElementDrawable.swift)
 */
export function elementDrawable(el: ExcalidrawElement, options: Options): Drawable | null {
  const w = el.width;
  const h = el.height;
  const rounded = el.roundness !== null;

  switch (el.type) {
    case "rectangle":
    case "embeddable":
    case "iframe":
      return rounded
        ? generator.polygon(roundedRectanglePoints(w, h), options)
        : generator.rectangle(0, 0, w, h, options);
    case "diamond":
      return generator.polygon(
        [
          [w / 2, 0],
          [w, h / 2],
          [w / 2, h],
          [0, h / 2],
        ],
        options,
      );
    case "ellipse":
      return generator.ellipse(w / 2, h / 2, w, h, options);
    case "line":
      return linearDrawable(el.points, el.polygon || isLoop(el.points), rounded, options);
    case "arrow":
      return linearDrawable(el.points, false, rounded, options);
    default:
      return null;
  }
}
