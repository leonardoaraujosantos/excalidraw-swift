import { Point } from "@cyberdynecorp/excalidraw-math";
import { describe, expect, it } from "vitest";
import { BoundingBox } from "./bounding-box.js";
import { ElbowArrow } from "./elbow-arrow.js";

const box = (x: number, y: number, w: number, h: number) => new BoundingBox(x, y, x + w, y + h);

function expectOrthogonal(points: Point[]): void {
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i]!;
    const b = points[i + 1]!;
    expect(Math.abs(a.x - b.x) < 1e-6 || Math.abs(a.y - b.y) < 1e-6).toBe(true);
  }
}

describe("elbow arrow routing", () => {
  it("free endpoints produce an orthogonal route", () => {
    const route = ElbowArrow.route(new Point(0, 0), null, new Point(100, 60), null);
    expect(route.length).toBeGreaterThanOrEqual(2);
    expect(route[0]).toEqual(new Point(0, 0));
    expect(route[route.length - 1]).toEqual(new Point(100, 60));
    expectOrthogonal(route);
  });

  it("collinear horizontal endpoints route straight", () => {
    const route = ElbowArrow.route(new Point(0, 50), null, new Point(200, 50), null);
    expect(route[0]).toEqual(new Point(0, 50));
    expect(route[route.length - 1]).toEqual(new Point(200, 50));
    expectOrthogonal(route);
    for (const p of route) expect(p.y).toBeCloseTo(50, 6);
  });

  it("routes between two horizontally-separated boxes", () => {
    const route = ElbowArrow.route(
      new Point(100, 50),
      box(0, 0, 100, 100),
      new Point(300, 50),
      box(300, 0, 100, 100),
    );
    expect(route[0]).toEqual(new Point(100, 50));
    expect(route[route.length - 1]).toEqual(new Point(300, 50));
    expectOrthogonal(route);
  });

  it("routes between vertically-stacked boxes", () => {
    const route = ElbowArrow.route(
      new Point(50, 100),
      box(0, 0, 100, 100),
      new Point(50, 300),
      box(0, 300, 100, 100),
    );
    expect(route[0]).toEqual(new Point(50, 100));
    expect(route[route.length - 1]).toEqual(new Point(50, 300));
    expectOrthogonal(route);
  });

  it("diagonal boxes produce at least one bend", () => {
    const route = ElbowArrow.route(
      new Point(80, 40),
      box(0, 0, 80, 80),
      new Point(260, 240),
      box(260, 200, 80, 80),
    );
    expectOrthogonal(route);
    expect(route.length).toBeGreaterThanOrEqual(3);
  });
});

describe("elbow arrow segment editing", () => {
  const lShape = [new Point(0, 0), new Point(50, 0), new Point(50, 100), new Point(150, 100)];

  it("fixable segments exclude endpoints", () => {
    const segments = ElbowArrow.fixableSegments(lShape);
    expect(segments.map((s) => s.index)).toEqual([2]);
    expect(segments[0]!.isHorizontal).toBe(false);
    expect(segments[0]!.midpoint).toEqual(new Point(50, 50));
  });

  it("no fixable segments for short paths", () => {
    expect(ElbowArrow.fixableSegments([new Point(0, 0), new Point(100, 0)])).toHaveLength(0);
    expect(
      ElbowArrow.fixableSegments([new Point(0, 0), new Point(50, 0), new Point(50, 50)]),
    ).toHaveLength(0);
  });

  it("moving a vertical segment shifts it horizontally", () => {
    const moved = ElbowArrow.moveSegment(lShape, 2, new Point(90, 50));
    expect(moved.index).toBe(2);
    expect(moved.points[1]).toEqual(new Point(90, 0));
    expect(moved.points[2]).toEqual(new Point(90, 100));
    expect(moved.points[0]).toEqual(new Point(0, 0));
    expect(moved.points[3]).toEqual(new Point(150, 100));
    expectOrthogonal(moved.points);
  });

  it("moving a horizontal segment shifts it vertically", () => {
    const points = [new Point(0, 0), new Point(0, 50), new Point(100, 50), new Point(100, 150)];
    const moved = ElbowArrow.moveSegment(points, 2, new Point(50, 80));
    expect(moved.points[1]).toEqual(new Point(0, 80));
    expect(moved.points[2]).toEqual(new Point(100, 80));
    expectOrthogonal(moved.points);
  });

  it("dragging the first segment inserts a bend", () => {
    const points = [new Point(0, 0), new Point(100, 0), new Point(100, 80)];
    const moved = ElbowArrow.moveSegment(points, 1, new Point(50, 30));
    expect(moved.points.length).toBe(4);
    expect(moved.index).toBe(2);
    expect(moved.points[0]).toEqual(new Point(0, 0));
    expect(moved.points[moved.points.length - 1]).toEqual(new Point(100, 80));
    expectOrthogonal(moved.points);
  });

  it("dragging the last segment inserts a bend", () => {
    const points = [new Point(0, 0), new Point(0, 80), new Point(120, 80)];
    const moved = ElbowArrow.moveSegment(points, 2, new Point(60, 50));
    expect(moved.points.length).toBe(4);
    expect(moved.points[0]).toEqual(new Point(0, 0));
    expect(moved.points[moved.points.length - 1]).toEqual(new Point(120, 80));
    expectOrthogonal(moved.points);
  });

  it("followEndpoints preserves interior segments", () => {
    const moved = ElbowArrow.followEndpoints(lShape, new Point(-20, 10), new Point(180, 130));
    expect(moved[0]).toEqual(new Point(-20, 10));
    expect(moved[moved.length - 1]).toEqual(new Point(180, 130));
    expect(moved[1]!.x).toBe(50);
    expect(moved[2]!.x).toBe(50);
    expectOrthogonal(moved);
  });
});
