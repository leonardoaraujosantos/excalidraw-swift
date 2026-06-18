import { Point } from "@cyberdynecorp/excalidraw-math";
import {
  type ArrowElement,
  type ExcalidrawElement,
  Scene,
  defaultBase,
} from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { EditorController } from "./controller.js";
import { pointerEvent } from "./pointer-event.js";

function expectOrthogonal(points: Point[]): void {
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i]!;
    const b = points[i + 1]!;
    expect(Math.abs(a.x - b.x) < 1e-6 || Math.abs(a.y - b.y) < 1e-6).toBe(true);
  }
}

function arrowEl(
  id: string,
  points: [number, number][],
  elbowed: boolean,
  extra: Partial<ArrowElement> = {},
): ExcalidrawElement {
  return {
    ...defaultBase(id, { width: 150, height: 100 }),
    type: "arrow",
    points,
    startBinding: null,
    endBinding: null,
    startArrowhead: null,
    endArrowhead: "arrow",
    elbowed,
    ...extra,
  };
}

function globalPoints(ec: EditorController, id: string): Point[] {
  const el = ec.scene.element(id)!;
  if (el.type !== "arrow") return [];
  return el.points.map((p) => new Point(el.x + p[0], el.y + p[1]));
}

function fourPointElbow(): EditorController {
  return new EditorController(
    new Scene([
      arrowEl(
        "arrow",
        [
          [0, 0],
          [50, 0],
          [50, 100],
          [150, 100],
        ],
        true,
      ),
    ]),
  );
}

describe("elbow arrow editor", () => {
  it("creating an elbow arrow produces orthogonal points", () => {
    const ec = new EditorController();
    ec.currentItem.elbowed = true;
    ec.setTool("arrow");
    ec.pointerDown(pointerEvent(new Point(0, 0), "down"));
    ec.pointerMove(pointerEvent(new Point(120, 80), "move"));
    ec.pointerUp(pointerEvent(new Point(120, 80), "up"));
    const arrow = ec.scene.visibleElements[0]!;
    if (arrow.type === "arrow") {
      expect(arrow.elbowed).toBe(true);
      expect(arrow.points.length).toBeGreaterThanOrEqual(2);
      expectOrthogonal(arrow.points.map((p) => new Point(p[0], p[1])));
    }
  });

  it("a non-elbow arrow stays two points", () => {
    const ec = new EditorController();
    ec.setTool("arrow");
    ec.pointerDown(pointerEvent(new Point(0, 0), "down"));
    ec.pointerMove(pointerEvent(new Point(120, 80), "move"));
    ec.pointerUp(pointerEvent(new Point(120, 80), "up"));
    const arrow = ec.scene.visibleElements[0]!;
    if (arrow.type === "arrow") {
      expect(arrow.elbowed).toBe(false);
      expect(arrow.points.length).toBe(2);
    }
  });

  it("moving a segment pins a fixed segment", () => {
    const ec = fourPointElbow();
    ec.moveElbowSegment("arrow", 2, new Point(90, 50));
    const el = ec.scene.element("arrow")!;
    if (el.type === "arrow") {
      expect(el.fixedSegments?.length).toBe(1);
      expect(el.fixedSegments?.[0]?.index).toBe(2);
    }
    const g = globalPoints(ec, "arrow");
    expect(g[1]!.x).toBeCloseTo(90, 9);
    expect(g[2]!.x).toBeCloseTo(90, 9);
  });

  it("segment handles via the linear-edit drag", () => {
    const ec = fourPointElbow();
    expect(ec.beginLinearEdit(new Point(50, 50))).toBe(true);
    ec.pointerDown(pointerEvent(new Point(50, 50), "down"));
    ec.pointerMove(pointerEvent(new Point(85, 50), "move"));
    ec.pointerUp(pointerEvent(new Point(85, 50), "up"));
    const el = ec.scene.element("arrow")!;
    if (el.type === "arrow") {
      expect(el.fixedSegments?.[0]?.index).toBe(2);
      expect(el.x + el.points[1]![0]).toBeCloseTo(85, 9);
    }
  });

  it("a pinned segment survives an endpoint reroute", () => {
    const ec = fourPointElbow();
    ec.moveElbowSegment("arrow", 2, new Point(90, 50));
    ec.store.modifyScene((scene) => {
      const arrow = scene.element("arrow");
      if (arrow === undefined || arrow.type !== "arrow") return;
      const last = arrow.points[arrow.points.length - 1]!;
      const points = [...arrow.points];
      points[points.length - 1] = [last[0] + 40, last[1] + 30];
      scene.replace({ ...arrow, points });
    });
    ec.routeElbowArrow("arrow");
    const g = globalPoints(ec, "arrow");
    expect(g[1]!.x).toBeCloseTo(90, 6);
    expect(g[2]!.x).toBeCloseTo(90, 6);
    expectOrthogonal(g);
  });

  it("dragging the first segment inserts a bend and pins", () => {
    const ec = new EditorController(
      new Scene([
        arrowEl(
          "arrow",
          [
            [0, 0],
            [100, 0],
            [100, 80],
          ],
          true,
        ),
      ]),
    );
    expect(ec.beginLinearEdit(new Point(50, 0))).toBe(true);
    ec.pointerDown(pointerEvent(new Point(50, 0), "down"));
    ec.pointerMove(pointerEvent(new Point(50, 30), "move"));
    ec.pointerUp(pointerEvent(new Point(50, 30), "up"));
    const el = ec.scene.element("arrow")!;
    if (el.type === "arrow") {
      expect(el.points.length).toBeGreaterThanOrEqual(4);
      expect((el.fixedSegments?.length ?? 0) > 0).toBe(true);
    }
  });

  it("resetElbowShape clears pins and re-routes (undoable)", () => {
    const ec = fourPointElbow();
    ec.moveElbowSegment("arrow", 2, new Point(90, 50));
    ec.store.commit();
    expect(ec.hasFixedSegments("arrow")).toBe(true);
    ec.resetElbowShape("arrow");
    expect(ec.hasFixedSegments("arrow")).toBe(false);
    expect(ec.undo()).toBe(true);
    expect(ec.hasFixedSegments("arrow")).toBe(true);
  });

  it("a bound elbow arrow re-routes orthogonally", () => {
    const a: ExcalidrawElement = {
      ...defaultBase("a", { x: 0, y: 0, width: 100, height: 100, backgroundColor: "#f00" }),
      type: "rectangle",
    };
    const b: ExcalidrawElement = {
      ...defaultBase("b", { x: 300, y: 0, width: 100, height: 100, backgroundColor: "#f00" }),
      type: "rectangle",
    };
    const arrow = arrowEl(
      "arrow",
      [
        [0, 0],
        [200, 50],
      ],
      true,
      {
        startBinding: { elementId: "a", fixedPoint: [1, 0.5], mode: "orbit" },
        endBinding: { elementId: "b", fixedPoint: [0, 0.5], mode: "orbit" },
      },
    );
    const withPos = { ...arrow, x: 100, y: 50 };
    const ec = new EditorController(new Scene([a, b, withPos]));
    ec.routeElbowArrow("arrow");
    expectOrthogonal(globalPoints(ec, "arrow"));
  });
});
