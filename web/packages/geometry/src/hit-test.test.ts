import { Point } from "@cyberdynecorp/excalidraw-math";
import { describe, expect, it } from "vitest";
import { distanceToElement, hit, isPointInside, shouldTestInside } from "./hit-test.js";
import { arrowEl, freedrawEl, imageEl, rectEl, shapeEl, textEl } from "./test-helpers.js";

const FILLED = "#ff0000";

describe("hit testing", () => {
  it("shouldTestInside", () => {
    expect(shouldTestInside(rectEl({ w: 100, h: 100, bg: FILLED }))).toBe(true);
    expect(shouldTestInside(rectEl({ w: 100, h: 100, bg: "transparent" }))).toBe(false);
    expect(shouldTestInside(textEl({ w: 50, h: 20 }))).toBe(true);
    expect(shouldTestInside(imageEl({ w: 50, h: 50 }))).toBe(true);
    expect(shouldTestInside(arrowEl([], { w: 100, h: 0 }))).toBe(false);
  });

  it("8-digit hex with 00 alpha is transparent", () => {
    expect(shouldTestInside(rectEl({ w: 100, h: 100, bg: "#ff000000" }))).toBe(false);
  });

  it("embeddable and iframe are inside-draggable", () => {
    expect(shouldTestInside(shapeEl("embeddable", { w: 100, h: 100 }))).toBe(true);
    expect(shouldTestInside(shapeEl("iframe", { w: 100, h: 100 }))).toBe(true);
  });

  it("filled rectangle hit", () => {
    const rect = rectEl({ x: 0, y: 0, w: 100, h: 100, bg: FILLED });
    expect(hit(rect, new Point(50, 50), 10)).toBe(true);
    expect(hit(rect, new Point(105, 50), 10)).toBe(true);
    expect(hit(rect, new Point(200, 50), 10)).toBe(false);
  });

  it("transparent rectangle hits only on the outline", () => {
    const rect = rectEl({ x: 0, y: 0, w: 100, h: 100, bg: "transparent" });
    expect(hit(rect, new Point(50, 50), 10)).toBe(false);
    expect(hit(rect, new Point(2, 50), 10)).toBe(true);
  });

  it("ellipse hit", () => {
    const ellipse = shapeEl("ellipse", { x: 0, y: 0, w: 100, h: 100, bg: FILLED });
    expect(hit(ellipse, new Point(50, 50), 5)).toBe(true);
    expect(hit(ellipse, new Point(95, 95), 5)).toBe(false);
  });

  it("arrow hit on the line", () => {
    const arrow = arrowEl(
      [
        [0, 0],
        [100, 0],
      ],
      { w: 100, h: 0 },
    );
    expect(hit(arrow, new Point(50, 3), 10)).toBe(true);
    expect(hit(arrow, new Point(50, 30), 10)).toBe(false);
  });

  it("rotated rectangle interior hit", () => {
    const rect = rectEl({ x: 0, y: 0, w: 100, h: 20, angle: Math.PI / 2, bg: FILLED });
    expect(hit(rect, new Point(50, 50), 2)).toBe(true);
    expect(hit(rect, new Point(90, 10), 2)).toBe(false);
  });

  it("closed freedraw is inside-draggable", () => {
    const loop = freedrawEl(
      [
        [0, 0],
        [50, 0],
        [50, 50],
        [0, 50],
        [0, 0],
      ],
      { w: 50, h: 50, bg: FILLED },
    );
    expect(shouldTestInside(loop)).toBe(true);
    expect(isPointInside(loop, new Point(25, 25))).toBe(true);
  });

  it("bound text makes a shape inside-draggable", () => {
    const rect = rectEl({
      w: 100,
      h: 100,
      bg: "transparent",
      boundElements: [{ id: "t", type: "text" }],
    });
    expect(shouldTestInside(rect)).toBe(true);
  });

  it("distance to rectangle outline", () => {
    const rect = rectEl({ x: 0, y: 0, w: 100, h: 100 });
    expect(distanceToElement(rect, new Point(110, 50))).toBeCloseTo(10, 6);
  });

  it("single-point freedraw distance and hit", () => {
    const free = freedrawEl([[0, 0]], { x: 10, y: 10 });
    expect(distanceToElement(free, new Point(13, 14))).toBeCloseTo(5, 6);
    expect(hit(free, new Point(13, 14), 10)).toBe(true);
  });

  it("diamond interior and outline", () => {
    const diamond = shapeEl("diamond", { x: 0, y: 0, w: 100, h: 100, bg: FILLED });
    expect(hit(diamond, new Point(50, 50), 2)).toBe(true);
    expect(hit(diamond, new Point(5, 5), 2)).toBe(false);
    expect(hit(diamond, new Point(25, 50), 4)).toBe(true);
  });
});
