import { Point } from "@cyberdynecorp/excalidraw-math";
import {
  type ExcalidrawElement,
  type LocalPoint,
  Scene,
  defaultBase,
} from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { EditorController } from "./controller.js";
import { pointerEvent } from "./pointer-event.js";

function lineEditor(): EditorController {
  const el: ExcalidrawElement = {
    ...defaultBase("L", { width: 100, height: 0 }),
    type: "line",
    points: [
      [0, 0],
      [50, 0],
      [100, 0],
    ],
    startBinding: null,
    endBinding: null,
    startArrowhead: null,
    endArrowhead: null,
    polygon: false,
  };
  return new EditorController(new Scene([el]));
}

function linePoints(ec: EditorController): LocalPoint[] {
  const el = ec.scene.element("L");
  return el?.type === "line" ? el.points : [];
}

describe("linear point editing", () => {
  it("begins point-edit mode on a line", () => {
    const ec = lineEditor();
    expect(ec.beginLinearEdit(new Point(50, 0))).toBe(true);
    expect(ec.editingLinearID).toBe("L");
    expect(ec.linearEditHandles()).not.toBeNull();
    expect(ec.transformHandles().size).toBe(0);
  });

  it("drags a point to move it", () => {
    const ec = lineEditor();
    ec.beginLinearEdit(new Point(50, 0));
    ec.pointerDown(pointerEvent(new Point(50, 0), "down"));
    ec.pointerMove(pointerEvent(new Point(50, 40), "move"));
    ec.pointerUp(pointerEvent(new Point(50, 40), "up"));
    expect(linePoints(ec)[1]).toEqual([50, 40]);
  });

  it("drags a midpoint to insert a point", () => {
    const ec = lineEditor();
    ec.beginLinearEdit(new Point(50, 0));
    ec.pointerDown(pointerEvent(new Point(25, 0), "down"));
    ec.pointerMove(pointerEvent(new Point(25, 30), "move"));
    ec.pointerUp(pointerEvent(new Point(25, 30), "up"));
    const pts = linePoints(ec);
    expect(pts.length).toBe(4);
    expect(pts[1]).toEqual([25, 30]);
  });

  it("edit is undoable", () => {
    const ec = lineEditor();
    ec.beginLinearEdit(new Point(50, 0));
    ec.pointerDown(pointerEvent(new Point(50, 0), "down"));
    ec.pointerMove(pointerEvent(new Point(50, 40), "move"));
    ec.pointerUp(pointerEvent(new Point(50, 40), "up"));
    expect(ec.undo()).toBe(true);
    expect(linePoints(ec)[1]).toEqual([50, 0]);
  });

  it("clicking away exits edit mode", () => {
    const ec = lineEditor();
    ec.beginLinearEdit(new Point(50, 0));
    expect(ec.editingLinearID).toBe("L");
    ec.pointerDown(pointerEvent(new Point(500, 500), "down"));
    expect(ec.editingLinearID).toBeNull();
  });

  it("changing tool exits edit mode", () => {
    const ec = lineEditor();
    ec.beginLinearEdit(new Point(50, 0));
    ec.setTool("rectangle");
    expect(ec.editingLinearID).toBeNull();
  });
});
