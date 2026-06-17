import { Point } from "@xs/math";
import { type ExcalidrawElement, defaultBase } from "@xs/model";
import { describe, expect, it } from "vitest";
import type { EditorController } from "./controller.js";
import { pointerEvent } from "./pointer-event.js";
import { makeEditor } from "./test-helpers.js";

function shape(id: string, x: number, y: number, w = 60, h = 60): ExcalidrawElement {
  return {
    ...defaultBase(id, { x, y, width: w, height: h, backgroundColor: "#ff0000" }),
    type: "rectangle",
  };
}

function arrowEnd(ec: EditorController, arrowID: string): Point {
  const e = ec.scene.element(arrowID)!;
  if (e.type !== "arrow") return Point.zero;
  const last = e.points[e.points.length - 1]!;
  return new Point(e.x + last[0], e.y + last[1]);
}

function drawArrow(ec: EditorController, from: Point, to: Point): void {
  ec.setTool("arrow");
  ec.pointerDown(pointerEvent(from, "down"));
  ec.pointerMove(pointerEvent(to, "move"));
  ec.pointerUp(pointerEvent(to, "up"));
}

const arrowOf = (ec: EditorController) => ec.scene.visibleElements.find((e) => e.type === "arrow");

describe("arrow binding", () => {
  it("binds an arrow to shapes at both ends", () => {
    const ec = makeEditor([shape("a", 0, 0), shape("b", 300, 0)]);
    drawArrow(ec, new Point(30, 30), new Point(330, 30));
    const arrow = arrowOf(ec)!;
    if (arrow.type === "arrow") {
      expect(arrow.startBinding?.elementId).toBe("a");
      expect(arrow.endBinding?.elementId).toBe("b");
    }
    expect(ec.scene.element("a")?.boundElements?.[0]?.type).toBe("arrow");
  });

  it("a bound arrow follows when its shape moves", () => {
    const ec = makeEditor([shape("a", 0, 0), shape("b", 300, 0)]);
    drawArrow(ec, new Point(30, 30), new Point(330, 30));
    const arrowID = arrowOf(ec)!.id;
    const before = arrowEnd(ec, arrowID);

    ec.setTool("selection");
    ec.pointerDown(pointerEvent(new Point(330, 52), "down"));
    ec.pointerMove(pointerEvent(new Point(330, 152), "move"));
    ec.pointerUp(pointerEvent(new Point(330, 152), "up"));

    const after = arrowEnd(ec, arrowID);
    expect(after.y - before.y).toBeCloseTo(100, 6);
  });

  it("binding can be disabled", () => {
    const ec = makeEditor([shape("a", 0, 0), shape("b", 300, 0)]);
    ec.bindingEnabled = false;
    drawArrow(ec, new Point(30, 30), new Point(330, 30));
    const arrow = arrowOf(ec)!;
    if (arrow.type === "arrow") {
      expect(arrow.startBinding).toBeNull();
      expect(arrow.endBinding).toBeNull();
    }
  });
});
