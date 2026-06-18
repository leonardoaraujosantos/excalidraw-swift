import { type Point, Vector } from "@cyberdynecorp/excalidraw-math";
import type { BoundingBox } from "./bounding-box.js";

/** One of the four cardinal directions an elbow-arrow segment can travel. */
export type Heading = "up" | "right" | "down" | "left";

/** Unit vector for the heading (y-down coordinates). */
export function headingVector(h: Heading): Vector {
  switch (h) {
    case "up":
      return new Vector(0, -1);
    case "right":
      return new Vector(1, 0);
    case "down":
      return new Vector(0, 1);
    case "left":
      return new Vector(-1, 0);
  }
}

export function isHorizontal(h: Heading): boolean {
  return h === "left" || h === "right";
}

export function isVertical(h: Heading): boolean {
  return !isHorizontal(h);
}

/** The opposite heading (`flipHeading`). */
export function flippedHeading(h: Heading): Heading {
  switch (h) {
    case "up":
      return "down";
    case "right":
      return "left";
    case "down":
      return "up";
    case "left":
      return "right";
  }
}

/** Quantize an arbitrary vector to the nearest cardinal heading (`vectorToHeading`). */
export function headingFromVector(v: Vector): Heading {
  const x = v.u;
  const y = v.v;
  const absX = Math.abs(x);
  const absY = Math.abs(y);
  if (x > absY) return "right";
  if (x <= -absY) return "left";
  if (y > absX) return "down";
  return "up";
}

/** Heading from `origin` toward `point` (`headingForPoint`). */
export function headingFromPoint(point: Point, origin: Point): Heading {
  return headingFromVector(new Vector(point.x - origin.x, point.y - origin.y));
}

/** The side of `box` that `point` lies toward (rectangle diagonal cones). */
export function headingFromBoxToward(box: BoundingBox, point: Point): Heading {
  const cx = (box.minX + box.maxX) / 2;
  const cy = (box.minY + box.maxY) / 2;
  const hw = Math.max(box.width / 2, 1e-9);
  const hh = Math.max(box.height / 2, 1e-9);
  const nx = (point.x - cx) / hw;
  const ny = (point.y - cy) / hh;
  if (Math.abs(nx) > Math.abs(ny)) return nx > 0 ? "right" : "left";
  return ny > 0 ? "down" : "up";
}

export const Heading = {
  vector: headingVector,
  isHorizontal,
  isVertical,
  flipped: flippedHeading,
  fromVector: headingFromVector,
  fromPoint: headingFromPoint,
  fromBoxToward: headingFromBoxToward,
} as const;
