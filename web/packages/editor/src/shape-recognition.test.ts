import { BoundingBox, ShapeGenerator } from "@cyberdynecorp/excalidraw-geometry";
import { Point } from "@cyberdynecorp/excalidraw-math";
import { type ExcalidrawElement, Scene, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { EditorController } from "./controller.js";

function tracedFreedraw(
  corners: Point[],
  closed: boolean,
  steps = 12,
  id = "f",
  stroke = "#e03131",
): EditorController {
  const path = closed ? [...corners, corners[0]!] : corners;
  const points: [number, number][] = [];
  for (let i = 0; i < path.length - 1; i++) {
    const a = path[i]!;
    const b = path[i + 1]!;
    for (let s = 0; s < steps; s++) {
      const t = s / steps;
      points.push([a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t]);
    }
  }
  points.push([path[path.length - 1]!.x, path[path.length - 1]!.y]);
  const el: ExcalidrawElement = {
    ...defaultBase(id, { strokeColor: stroke, strokeWidth: 3 }),
    type: "freedraw",
    points,
    pressures: [],
    simulatePressure: true,
  };
  return new EditorController(new Scene([el]));
}

describe("shape recognition", () => {
  it("replaces a square stroke with a rectangle", () => {
    const ec = tracedFreedraw(
      [new Point(10, 10), new Point(110, 10), new Point(110, 110), new Point(10, 110)],
      true,
    );
    expect(ec.recognizeFreedraw("f")).toBe("rectangle");
    const el = ec.scene.element("f")!;
    expect(el.type).toBe("rectangle");
    expect(el.width).toBeCloseTo(100, 0);
    expect(el.strokeColor).toBe("#e03131");
    expect([...ec.selectedIDs]).toEqual(["f"]);
  });

  it("replaces a triangle stroke with a closed polyline", () => {
    const ec = tracedFreedraw([new Point(50, 0), new Point(100, 100), new Point(0, 100)], true);
    expect(ec.recognizeFreedraw("f")).toBe("triangle");
    const el = ec.scene.element("f")!;
    expect(el.type).toBe("line");
    if (el.type === "line") {
      expect(el.polygon).toBe(true);
      expect(el.points.length).toBe(4);
    }
  });

  it("recognition is undoable", () => {
    const ec = tracedFreedraw(
      [new Point(10, 10), new Point(110, 10), new Point(110, 110), new Point(10, 110)],
      true,
    );
    ec.recognizeFreedraw("f");
    expect(ec.undo()).toBe(true);
    expect(ec.scene.element("f")?.type).toBe("freedraw");
  });

  it("replaces a star stroke with a closed polyline", () => {
    const box = new BoundingBox(0, 0, 200, 200);
    const path = [...ShapeGenerator.star(box, 5)];
    path.push(path[0]!);
    const points: [number, number][] = [];
    for (let i = 0; i < path.length - 1; i++) {
      const a = path[i]!;
      const b = path[i + 1]!;
      for (let s = 0; s < 6; s++) {
        const t = s / 6;
        points.push([a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t]);
      }
    }
    const el: ExcalidrawElement = {
      ...defaultBase("f", { strokeColor: "#1971c2" }),
      type: "freedraw",
      points,
      pressures: [],
      simulatePressure: true,
    };
    const ec = new EditorController(new Scene([el]));
    expect(ec.recognizeFreedraw("f")).toBe("star");
    const result = ec.scene.element("f")!;
    if (result.type === "line") {
      expect(result.polygon).toBe(true);
      expect(result.points.length).toBe(11);
    }
    expect(result.strokeColor).toBe("#1971c2");
  });

  it("ignores non-freedraw elements", () => {
    const ec = new EditorController(new Scene([{ ...defaultBase("r"), type: "rectangle" }]));
    expect(ec.recognizeFreedraw("r")).toBeNull();
  });
});
