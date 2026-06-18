import { Point } from "@cyberdynecorp/excalidraw-math";
import type { BoundingBox } from "./bounding-box.js";

export const DEFAULT_SNAP_DISTANCE = 8;

/** The result of snapping: an offset to apply plus the matched guide lines. */
export interface SnapResult {
  offsetX: number;
  offsetY: number;
  /** Scene x-coordinates of vertical guide lines (matched edges/centres). */
  verticalLines: number[];
  /** Scene y-coordinates of horizontal guide lines. */
  horizontalLines: number[];
}

export const NO_SNAP: SnapResult = {
  offsetX: 0,
  offsetY: 0,
  verticalLines: [],
  horizontalLines: [],
};

/** Snap a point to the nearest grid intersection. */
export function snapToGrid(point: Point, gridSize: number): Point {
  if (gridSize <= 0) return point;
  return new Point(
    Math.round(point.x / gridSize) * gridSize,
    Math.round(point.y / gridSize) * gridSize,
  );
}

function bestSnap(
  moving: number[],
  statics: number[],
  threshold: number,
): { offset: number; line: number | null } {
  let best: { offset: number; line: number } | null = null;
  for (const m of moving) {
    for (const s of statics) {
      const delta = s - m;
      if (
        Math.abs(delta) <= threshold &&
        (best === null || Math.abs(delta) < Math.abs(best.offset))
      ) {
        best = { offset: delta, line: s };
      }
    }
  }
  return { offset: best?.offset ?? 0, line: best?.line ?? null };
}

/** Snap `moving` to the edges/centres of `statics` within `threshold`. */
export function snap(moving: BoundingBox, statics: BoundingBox[], threshold: number): SnapResult {
  const movingX = [moving.minX, (moving.minX + moving.maxX) / 2, moving.maxX];
  const movingY = [moving.minY, (moving.minY + moving.maxY) / 2, moving.maxY];
  const staticX = statics.flatMap((b) => [b.minX, (b.minX + b.maxX) / 2, b.maxX]);
  const staticY = statics.flatMap((b) => [b.minY, (b.minY + b.maxY) / 2, b.maxY]);

  const x = bestSnap(movingX, staticX, threshold);
  const y = bestSnap(movingY, staticY, threshold);

  return {
    offsetX: x.offset,
    offsetY: y.offset,
    verticalLines: x.line === null ? [] : [x.line],
    horizontalLines: y.line === null ? [] : [y.line],
  };
}

interface Span {
  lo: number;
  hi: number;
}

function overlaps(aLo: number, aHi: number, bLo: number, bHi: number): boolean {
  return aLo <= bHi && bLo <= aHi;
}

function gapSnap1D(
  movingLo: number,
  movingHi: number,
  spans: Span[],
  threshold: number,
): { offset: number; lines: number[] } {
  const movingWidth = movingHi - movingLo;
  const movingCenter = (movingLo + movingHi) / 2;
  const sorted = [...spans].sort((p, q) => p.lo - q.lo);
  let best: { offset: number; lines: number[] } | null = null;

  const consider = (offset: number, lines: number[]): void => {
    if (Math.abs(offset) > threshold) return;
    if (best === null || Math.abs(offset) < Math.abs(best.offset)) best = { offset, lines };
  };

  for (let i = 0; i < sorted.length; i++) {
    for (let j = i + 1; j < sorted.length; j++) {
      const a = sorted[i]!;
      const b = sorted[j]!;
      if (a.hi > b.lo) continue;
      const gap = b.lo - a.hi;
      if (gap >= movingWidth) consider((a.hi + b.lo) / 2 - movingCenter, [a.hi, b.lo]);
      consider(b.hi + gap - movingLo, [b.hi, b.hi + gap]);
      consider(a.lo - gap - movingHi, [a.lo - gap, a.lo]);
    }
  }
  return best ?? { offset: 0, lines: [] };
}

/** Gap (distribution) snapping: centre `moving` in a gap or repeat an existing gap. */
export function gapSnap(
  moving: BoundingBox,
  statics: BoundingBox[],
  threshold: number,
): SnapResult {
  const xSpans = statics
    .filter((b) => overlaps(b.minY, b.maxY, moving.minY, moving.maxY))
    .map((b) => ({ lo: b.minX, hi: b.maxX }));
  const x = gapSnap1D(moving.minX, moving.maxX, xSpans, threshold);

  const ySpans = statics
    .filter((b) => overlaps(b.minX, b.maxX, moving.minX, moving.maxX))
    .map((b) => ({ lo: b.minY, hi: b.maxY }));
  const y = gapSnap1D(moving.minY, moving.maxY, ySpans, threshold);

  return { offsetX: x.offset, offsetY: y.offset, verticalLines: x.lines, horizontalLines: y.lines };
}
