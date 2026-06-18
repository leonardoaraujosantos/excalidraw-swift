import { BoundingBox } from "@cyberdynecorp/excalidraw-geometry";
import { Point } from "@cyberdynecorp/excalidraw-math";
import {
  type ExcalidrawElement,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { MIN_SIZE, Transform } from "./transform.js";

const box = new BoundingBox(0, 0, 100, 100);
const b4 = (x: BoundingBox) => [x.minX, x.minY, x.maxX, x.maxY];

describe("Transform", () => {
  it("resize corner", () => {
    expect(b4(Transform.resize(box, "bottomRight", new Point(150, 150)))).toEqual([0, 0, 150, 150]);
  });

  it("resize top-left moves origin", () => {
    expect(b4(Transform.resize(box, "topLeft", new Point(-20, -10)))).toEqual([-20, -10, 100, 100]);
  });

  it("resize from centre", () => {
    expect(b4(Transform.resize(box, "bottomRight", new Point(60, 60), false, true))).toEqual([
      40, 40, 60, 60,
    ]);
  });

  it("resize keep aspect", () => {
    const wide = new BoundingBox(0, 0, 100, 50);
    const r = Transform.resize(wide, "bottomRight", new Point(200, 60), true);
    expect(r.width / r.height).toBeCloseTo(2, 9);
    expect(b4(r)).toEqual([0, 0, 200, 100]);
  });

  it("resize clamps minimum size", () => {
    const r = Transform.resize(box, "bottomRight", new Point(0, 0));
    expect(r.width).toBeCloseTo(MIN_SIZE, 9);
    expect(r.height).toBeCloseTo(MIN_SIZE, 9);
  });

  it("resize normalizes a flip", () => {
    const r = Transform.resize(box, "right", new Point(-50, 50));
    expect(r.minX).toBe(-50);
    expect(r.maxX).toBe(0);
  });

  it("scales a box element", () => {
    const el: ExcalidrawElement = {
      ...defaultBase("r", { x: 10, y: 10, width: 20, height: 20 }),
      type: "rectangle",
    };
    const e = Transform.scale(el, box, new BoundingBox(0, 0, 200, 200));
    expect(e.x).toBe(20);
    expect(e.width).toBe(40);
  });

  it("scales linear points", () => {
    const el: ExcalidrawElement = {
      ...defaultBase("l"),
      type: "line",
      points: [
        [0, 0],
        [10, 5],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: null,
      polygon: false,
    };
    const e = Transform.scale(el, new BoundingBox(0, 0, 10, 5), new BoundingBox(0, 0, 20, 10));
    if (e.type === "line") expect(e.points[1]).toEqual([20, 10]);
  });

  it("scaling text scales the font size", () => {
    const el: ExcalidrawElement = {
      ...defaultBase("t", { width: 100, height: 40 }),
      type: "text",
      ...defaultTextProps({ fontSize: 20, text: "Hi" }),
    };
    const e = Transform.scale(el, new BoundingBox(0, 0, 100, 40), new BoundingBox(0, 0, 200, 80));
    if (e.type === "text") expect(e.fontSize).toBeCloseTo(40, 9);
  });

  it("translate", () => {
    const el: ExcalidrawElement = { ...defaultBase("r", { x: 5, y: 5 }), type: "rectangle" };
    const e = Transform.translate(el, 10, -3);
    expect(e.x).toBe(15);
    expect(e.y).toBe(2);
  });

  it("rotation angle", () => {
    expect(Transform.rotationAngle(new Point(50, 50), new Point(50, 0), false)).toBeCloseTo(0, 9);
    expect(Transform.rotationAngle(new Point(50, 50), new Point(100, 50), false)).toBeCloseTo(
      Math.PI / 2,
      9,
    );
  });

  it("rotation snaps to 15°", () => {
    const angle = Transform.rotationAngle(new Point(0, 0), new Point(2, -10), true);
    const step = Math.PI / 12;
    expect(Math.round(angle / step) * step).toBeCloseTo(angle, 9);
  });

  it("handle positions", () => {
    const h = Transform.handlePositions(box, 30);
    expect(h.size).toBe(9);
    expect(h.get("topLeft")).toEqual(new Point(0, 0));
    expect(h.get("bottomRight")).toEqual(new Point(100, 100));
    expect(h.get("rotation")).toEqual(new Point(50, -30));
  });
});
