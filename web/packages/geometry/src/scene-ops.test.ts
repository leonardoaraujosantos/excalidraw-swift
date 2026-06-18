import { Point } from "@cyberdynecorp/excalidraw-math";
import { describe, expect, it } from "vitest";
import { BoundingBox } from "./bounding-box.js";
import { cullVisible } from "./culling.js";
import { dirtyRegion } from "./dirty-region.js";
import { ShapeGenerator } from "./shape-generator.js";
import { NO_SNAP, gapSnap, snap, snapToGrid } from "./snapping.js";
import { rectEl } from "./test-helpers.js";

describe("culling", () => {
  const visible = new BoundingBox(0, 0, 100, 100);

  it("keeps on-screen, drops off-screen", () => {
    const on = rectEl({ x: 10, y: 10, w: 50, h: 50 });
    const off = { ...rectEl({ x: 1000, y: 1000, w: 50, h: 50 }), id: "off" };
    const result = cullVisible([{ ...on, id: "on" }, off], visible);
    expect(result.map((e) => e.id)).toEqual(["on"]);
  });

  it("keeps a partially-overlapping element", () => {
    expect(cullVisible([rectEl({ x: 80, y: 80, w: 50, h: 50 })], visible).length).toBe(1);
  });

  it("margin keeps a nearby element", () => {
    const nearby = rectEl({ x: 130, y: 10, w: 10, h: 10 });
    expect(cullVisible([nearby], visible, 0).length).toBe(0);
    expect(cullVisible([nearby], visible, 100).length).toBe(1);
  });
});

describe("dirty region", () => {
  const rect = (id: string, x: number, y: number) => ({
    ...rectEl({ x, y, w: 40, h: 40 }),
    id,
  });

  it("null when nothing changes", () => {
    const scene = [rect("a", 0, 0)];
    expect(dirtyRegion(scene, scene)).toBeNull();
  });

  it("added element region", () => {
    const region = dirtyRegion([], [rect("a", 10, 20)])!;
    expect([region.minX, region.minY, region.maxX, region.maxY]).toEqual([10, 20, 50, 60]);
  });

  it("removed element region", () => {
    const region = dirtyRegion([rect("a", 10, 20)], [])!;
    expect([region.minX, region.minY, region.maxX, region.maxY]).toEqual([10, 20, 50, 60]);
  });

  it("moved element unions old and new bounds", () => {
    const region = dirtyRegion([rect("a", 0, 0)], [rect("a", 100, 0)])!;
    expect([region.minX, region.minY, region.maxX, region.maxY]).toEqual([0, 0, 140, 40]);
  });

  it("unaffected elements are ignored", () => {
    const old = [rect("a", 0, 0), rect("b", 500, 500)];
    const next = [rect("a", 0, 10), rect("b", 500, 500)];
    const region = dirtyRegion(old, next)!;
    expect([region.minX, region.minY, region.maxX, region.maxY]).toEqual([0, 0, 40, 50]);
  });
});

describe("snapping", () => {
  it("snap to grid", () => {
    expect(snapToGrid(new Point(23, 38), 20)).toEqual(new Point(20, 40));
    expect(snapToGrid(new Point(5, 5), 0)).toEqual(new Point(5, 5));
  });

  it("object snap aligns left edges", () => {
    const result = snap(new BoundingBox(102, 200, 152, 240), [new BoundingBox(100, 0, 140, 40)], 8);
    expect(result.offsetX).toBeCloseTo(-2, 9);
    expect(result.verticalLines).toEqual([100]);
  });

  it("object snap centres", () => {
    const result = snap(new BoundingBox(40, 103, 60, 123), [new BoundingBox(0, 100, 100, 100)], 8);
    expect(result.offsetY).toBeCloseTo(-3, 9);
  });

  it("no snap beyond threshold", () => {
    const result = snap(new BoundingBox(200, 200, 220, 220), [new BoundingBox(0, 0, 20, 20)], 8);
    expect(result).toEqual(NO_SNAP);
  });
});

describe("gap snapping", () => {
  const box = (x: number, y: number, w: number, h: number) => new BoundingBox(x, y, x + w, y + h);

  it("centres between two neighbours", () => {
    const result = gapSnap(box(43, 0, 20, 20), [box(0, 0, 20, 20), box(80, 0, 20, 20)], 8);
    expect(result.offsetX).toBeCloseTo(-3, 9);
    expect(result.verticalLines).toEqual([20, 80]);
    expect(result.offsetY).toBe(0);
  });

  it("repeats the gap to the right", () => {
    const result = gapSnap(box(83, 0, 20, 20), [box(0, 0, 20, 20), box(40, 0, 20, 20)], 8);
    expect(result.offsetX).toBeCloseTo(-3, 9);
    expect(result.verticalLines.length).toBeGreaterThan(0);
  });

  it("no gap snap without perpendicular overlap", () => {
    const result = gapSnap(box(43, 0, 20, 20), [box(0, 200, 20, 20), box(80, 200, 20, 20)], 8);
    expect(result.offsetX).toBe(0);
    expect(result.verticalLines).toEqual([]);
  });

  it("vertical gap centering", () => {
    const result = gapSnap(box(0, 44, 20, 20), [box(0, 0, 20, 20), box(0, 80, 20, 20)], 8);
    expect(result.offsetY).toBeCloseTo(-4, 9);
    expect(result.horizontalLines).toEqual([20, 80]);
  });
});

describe("shape generator", () => {
  const box = new BoundingBox(0, 0, 100, 100);
  const withinBox = (pts: Point[], tol = 0.5) => {
    for (const p of pts) {
      expect(p.x).toBeGreaterThanOrEqual(box.minX - tol);
      expect(p.x).toBeLessThanOrEqual(box.maxX + tol);
      expect(p.y).toBeGreaterThanOrEqual(box.minY - tol);
      expect(p.y).toBeLessThanOrEqual(box.maxY + tol);
    }
  };

  it("regular polygon vertex count", () => {
    expect(ShapeGenerator.regularPolygon(5, box).length).toBe(5);
    expect(ShapeGenerator.regularPolygon(6, box).length).toBe(6);
    withinBox(ShapeGenerator.regularPolygon(6, box));
  });

  it("star has twice the points and alternating radii", () => {
    const star = ShapeGenerator.star(box, 5);
    expect(star.length).toBe(10);
    const c = new Point(50, 50);
    expect(star[0]!.distance(c)).toBeGreaterThan(star[1]!.distance(c));
    withinBox(star);
  });

  it("heart, cloud, bubble fit the box", () => {
    withinBox(ShapeGenerator.heart(box));
    withinBox(ShapeGenerator.cloud(box));
    withinBox(ShapeGenerator.speechBubble(box));
    expect(ShapeGenerator.heart(box).length).toBeGreaterThan(10);
    expect(ShapeGenerator.cloud(box).length).toBeGreaterThan(10);
  });
});
