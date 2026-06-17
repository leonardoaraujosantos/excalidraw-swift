import { Point } from "@xs/math";
import { describe, expect, it } from "vitest";
import { elementDrawable } from "./element-drawable.js";
import { buildRoughOptions } from "./rough-options.js";
import { arrow, diamond, ellipse, rect, text } from "./test-helpers.js";
import { Viewport } from "./viewport.js";

describe("Viewport", () => {
  it("scene↔view round-trips at zoom", () => {
    const v = new Viewport(10, 20, 2);
    expect(v.sceneToView(new Point(10, 10))).toEqual(new Point(40, 60));
    const back = v.viewToScene(v.sceneToView(new Point(7, 9)));
    expect(back.x).toBeCloseTo(7, 9);
    expect(back.y).toBeCloseTo(9, 9);
  });
});

describe("rough options", () => {
  it("passes the seed and disables multi-stroke for non-solid", () => {
    const o = buildRoughOptions(rect({ w: 100, h: 60 }));
    expect(o.disableMultiStroke).toBe(false);
    const dashed = buildRoughOptions(rect({ w: 100, h: 60, strokeStyle: "dashed" }));
    expect(dashed.disableMultiStroke).toBe(true);
    expect(dashed.strokeLineDash).toEqual([8, 8 + 2]);
  });

  it("dotted dash pattern", () => {
    expect(
      buildRoughOptions(rect({ w: 100, h: 60, strokeStyle: "dotted" })).strokeLineDash,
    ).toEqual([1.5, 6 + 2]);
  });

  it("transparent background means no fill", () => {
    expect(buildRoughOptions(rect({ w: 100, h: 60, bg: "transparent" })).fill).toBeUndefined();
  });

  it("opaque background fills with the colour and style", () => {
    const o = buildRoughOptions(rect({ w: 100, h: 60, bg: "#ff0000", fillStyle: "hachure" }));
    expect(o.fill).toBe("#ff0000");
    expect(o.fillStyle).toBe("hachure");
  });

  it("small shapes get reduced roughness", () => {
    const o = buildRoughOptions(rect({ w: 10, h: 10 }));
    expect(o.roughness).toBeLessThanOrEqual(2.5);
    expect(o.roughness).toBe(0.5);
  });

  it("ellipse sets curve fitting", () => {
    expect(buildRoughOptions(ellipse({ w: 100, h: 60, bg: "#fff" })).curveFitting).toBe(1);
  });
});

describe("element drawables", () => {
  const opts = (el: ReturnType<typeof rect>) => buildRoughOptions(el);

  it("rectangle produces stroke ops", () => {
    const el = rect({ w: 100, h: 40 });
    const d = elementDrawable(el, opts(el))!;
    expect(d.sets.length).toBeGreaterThan(0);
    expect(d.sets.some((s) => s.type === "path")).toBe(true);
  });

  it("filled rectangle has a fill set", () => {
    const el = rect({ w: 100, h: 40, bg: "#ff0000" });
    const d = elementDrawable(el, opts(el))!;
    expect(d.sets.some((s) => s.type === "fillPath" || s.type === "fillSketch")).toBe(true);
  });

  it("diamond and ellipse produce drawables", () => {
    const di = diamond({ w: 80, h: 60 });
    const el = ellipse({ w: 80, h: 60 });
    expect(elementDrawable(di, opts(di))!.sets.length).toBeGreaterThan(0);
    expect(elementDrawable(el, opts(el))!.sets.length).toBeGreaterThan(0);
  });

  it("arrow produces a linear drawable", () => {
    const el = arrow([
      [0, 0],
      [100, 20],
    ]);
    expect(elementDrawable(el, opts(el))!.sets.length).toBeGreaterThan(0);
  });

  it("returns null for text", () => {
    const el = text("hi", { w: 40, h: 20 });
    expect(elementDrawable(el, buildRoughOptions(el))).toBeNull();
  });
});
