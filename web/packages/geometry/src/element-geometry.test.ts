import { Point } from "@cyberdynecorp/excalidraw-math";
import { describe, expect, it } from "vitest";
import { BoundingBox } from "./bounding-box.js";
import { absoluteCoords, bounds, commonBounds } from "./element-geometry.js";
import { arrowEl, freedrawEl, lineEl, rectEl, shapeEl } from "./test-helpers.js";

const EPS = 6;

describe("BoundingBox", () => {
  it("from points", () => {
    const box = BoundingBox.fromPoints([new Point(1, 2), new Point(-3, 5), new Point(4, -1)])!;
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([-3, -1, 4, 5]);
    expect(box.width).toBe(7);
    expect(box.height).toBe(6);
  });

  it("empty points is null", () => {
    expect(BoundingBox.fromPoints([])).toBeNull();
  });

  it("contains", () => {
    const box = new BoundingBox(0, 0, 10, 10);
    expect(box.contains(new Point(5, 5))).toBe(true);
    expect(box.contains(new Point(11, 5))).toBe(false);
  });

  it("union", () => {
    const u = new BoundingBox(0, 0, 2, 2).union(new BoundingBox(1, 1, 4, 5));
    expect([u.minX, u.minY, u.maxX, u.maxY]).toEqual([0, 0, 4, 5]);
  });
});

describe("element geometry", () => {
  it("rectangle bounds", () => {
    const box = bounds(rectEl({ x: 10, y: 20, w: 100, h: 40 }));
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([10, 20, 110, 60]);
  });

  it("rotated rectangle bounds (90° swaps axes)", () => {
    const box = bounds(rectEl({ x: 10, y: 20, w: 100, h: 40, angle: Math.PI / 2 }));
    expect(box.minX).toBeCloseTo(40, EPS);
    expect(box.maxX).toBeCloseTo(80, EPS);
    expect(box.minY).toBeCloseTo(-10, EPS);
    expect(box.maxY).toBeCloseTo(90, EPS);
  });

  it("nonRotated flag ignores angle", () => {
    const box = bounds(rectEl({ x: 0, y: 0, w: 100, h: 40, angle: Math.PI / 4 }), true);
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([0, 0, 100, 40]);
  });

  it("ellipse rotated bounds swap axes", () => {
    const box = bounds(shapeEl("ellipse", { x: 0, y: 0, w: 100, h: 40, angle: Math.PI / 2 }));
    expect(box.width).toBeCloseTo(40, EPS);
    expect(box.height).toBeCloseTo(100, EPS);
  });

  it("diamond bounds match the box", () => {
    const box = bounds(shapeEl("diamond", { x: 0, y: 0, w: 80, h: 60 }));
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([0, 0, 80, 60]);
  });

  it("freedraw bounds from points", () => {
    const box = bounds(
      freedrawEl(
        [
          [0, 0],
          [30, 10],
          [10, 40],
        ],
        { x: 5, y: 5 },
      ),
    );
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([5, 5, 35, 45]);
  });

  it("common bounds", () => {
    const a = rectEl({ x: 0, y: 0, w: 10, h: 10 });
    const b = rectEl({ x: 20, y: 20, w: 10, h: 10 });
    const box = commonBounds([a, b])!;
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([0, 0, 30, 30]);
    expect(commonBounds([])).toBeNull();
  });

  it("absolute coords center", () => {
    const coords = absoluteCoords(rectEl({ x: 10, y: 10, w: 100, h: 20 }));
    expect(coords.cx).toBe(60);
    expect(coords.cy).toBe(20);
  });
});

describe("geometry edge cases", () => {
  it("arrow absolute coords from points", () => {
    const coords = absoluteCoords(
      arrowEl(
        [
          [0, 0],
          [100, 40],
        ],
        { x: 5, y: 5 },
      ),
    );
    expect([coords.x1, coords.y1, coords.x2, coords.y2]).toEqual([5, 5, 105, 45]);
  });

  it("line bounds from points", () => {
    const box = bounds(
      lineEl(
        [
          [0, 0],
          [100, 0],
          [100, 60],
          [0, 0],
        ],
        true,
        { x: 40, y: 200 },
      ),
    );
    expect([box.minX, box.minY, box.maxX, box.maxY]).toEqual([40, 200, 140, 260]);
  });

  it("rotated arrow bounds", () => {
    const box = bounds(
      arrowEl(
        [
          [0, 0],
          [100, 0],
        ],
        { angle: Math.PI / 2 },
      ),
    );
    expect(box.minX).toBeCloseTo(50, EPS);
    expect(box.maxX).toBeCloseTo(50, EPS);
    expect(box.minY).toBeCloseTo(-50, EPS);
    expect(box.maxY).toBeCloseTo(50, EPS);
  });

  it("rotated freedraw bounds", () => {
    const box = bounds(
      freedrawEl(
        [
          [0, 0],
          [100, 0],
        ],
        { angle: Math.PI / 2 },
      ),
    );
    expect(box.height).toBeCloseTo(100, EPS);
    expect(box.width).toBeCloseTo(0, EPS);
  });
});
