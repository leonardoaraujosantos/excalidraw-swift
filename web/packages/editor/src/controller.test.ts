import { Point } from "@cyberdynecorp/excalidraw-math";
import { Scene } from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { pointerEvent } from "./pointer-event.js";
import { drag, makeEditor, rect } from "./test-helpers.js";

describe("EditorController", () => {
  it("creates a rectangle by drag and reverts the tool", () => {
    const ec = makeEditor();
    ec.setTool("rectangle");
    drag(ec, new Point(10, 10), new Point(60, 40));
    expect(ec.scene.visibleElements.length).toBe(1);
    const e = ec.scene.visibleElements[0]!;
    expect(e.x).toBe(10);
    expect(e.width).toBe(50);
    expect(e.height).toBe(30);
    expect(ec.selectedIDs.has(e.id)).toBe(true);
    expect(ec.activeTool).toBe("selection");
  });

  it("creates a line by drag", () => {
    const ec = makeEditor();
    ec.setTool("line");
    drag(ec, new Point(0, 0), new Point(40, 20));
    const line = ec.scene.visibleElements[0]!;
    expect(line.type).toBe("line");
    if (line.type === "line") expect(line.points[line.points.length - 1]).toEqual([40, 20]);
  });

  it("a click without a drag creates nothing", () => {
    const ec = makeEditor();
    ec.setTool("rectangle");
    ec.pointerDown(pointerEvent(new Point(10, 10), "down"));
    ec.pointerUp(pointerEvent(new Point(10, 10), "up"));
    expect(ec.scene.visibleElements.length).toBe(0);
  });

  it("selects and moves, then undoes", () => {
    const ec = makeEditor([rect("r", 0, 0, 100, 100)]);
    drag(ec, new Point(50, 50), new Point(70, 60));
    expect(ec.scene.element("r")?.x).toBe(20);
    expect(ec.scene.element("r")?.y).toBe(10);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.element("r")?.x).toBe(0);
  });

  it("box-selects contained elements", () => {
    const ec = makeEditor([rect("a", 10, 10, 20, 20), rect("b", 200, 200, 20, 20)]);
    drag(ec, new Point(0, 0), new Point(100, 100));
    expect([...ec.selectedIDs]).toEqual(["a"]);
  });

  it("resizes via a handle, then undoes", () => {
    const ec = makeEditor([rect("r", 0, 0, 100, 100)]);
    drag(ec, new Point(50, 50), new Point(50, 50));
    expect([...ec.selectedIDs]).toEqual(["r"]);
    drag(ec, new Point(100, 100), new Point(160, 140));
    expect(ec.scene.element("r")?.width).toBe(160);
    expect(ec.scene.element("r")?.height).toBe(140);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.element("r")?.width).toBe(100);
  });

  it("rotates via the rotation handle", () => {
    const ec = makeEditor([rect("r", 0, 0, 100, 100)]);
    drag(ec, new Point(50, 50), new Point(50, 50));
    ec.pointerDown(pointerEvent(new Point(50, -30), "down"));
    ec.pointerMove(pointerEvent(new Point(150, 50), "move"));
    ec.pointerUp(pointerEvent(new Point(150, 50), "up"));
    expect(ec.scene.element("r")?.angle ?? 0).toBeCloseTo(Math.PI / 2, 1);
  });

  it("toggle multi-select", () => {
    const ec = makeEditor([rect("a", 0, 0, 40, 40), rect("b", 100, 0, 40, 40)]);
    drag(ec, new Point(20, 20), new Point(20, 20));
    ec.pointerDown(pointerEvent(new Point(120, 20), "down", { toggleSelection: true }));
    ec.pointerUp(pointerEvent(new Point(120, 20), "up", { toggleSelection: true }));
    expect(new Set(ec.selectedIDs)).toEqual(new Set(["a", "b"]));
  });

  it("deletes selected and undoes", () => {
    const ec = makeEditor([rect("r", 0, 0, 50, 50)]);
    ec.selectAll();
    ec.deleteSelected();
    expect(ec.scene.visibleElements.length).toBe(0);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(1);
  });

  it("locked elements are not selectable", () => {
    const locked = { ...rect("r", 0, 0, 100, 100), locked: true };
    const ec = makeEditor([locked]);
    drag(ec, new Point(50, 50), new Point(50, 50));
    expect(ec.selectedIDs.size).toBe(0);
  });

  it("transform handles appear only with a selection and the selection tool", () => {
    const ec = makeEditor([rect("r", 0, 0, 50, 50)]);
    expect(ec.transformHandles().size).toBe(0);
    drag(ec, new Point(25, 25), new Point(25, 25));
    expect(ec.transformHandles().size).toBe(9);
    ec.setTool("rectangle");
    expect(ec.transformHandles().size).toBe(0);
  });

  it("tool-locked keeps the tool after creating", () => {
    const ec = makeEditor();
    ec.setTool("rectangle");
    ec.toolLocked = true;
    drag(ec, new Point(0, 0), new Point(30, 30));
    expect(ec.activeTool).toBe("rectangle");
  });

  it("resize from centre grows symmetrically", () => {
    const ec = makeEditor([rect("r", 0, 0, 100, 100)]);
    drag(ec, new Point(50, 50), new Point(50, 50));
    ec.pointerDown(pointerEvent(new Point(100, 100), "down"));
    ec.pointerMove(pointerEvent(new Point(120, 120), "move", { alt: true }));
    ec.pointerUp(pointerEvent(new Point(120, 120), "up", { alt: true }));
    expect(ec.scene.element("r")?.x ?? 0).toBeLessThan(0);
  });

  it("freedraw accumulates points and pressures", () => {
    const ec = makeEditor();
    ec.setTool("freedraw");
    ec.pointerDown(pointerEvent(new Point(0, 0), "down", { type: "pen", pressure: 0.3 }));
    ec.pointerMove(pointerEvent(new Point(10, 5), "move", { type: "pen", pressure: 0.6 }));
    ec.pointerMove(pointerEvent(new Point(20, 0), "move", { type: "pen", pressure: 0.9 }));
    ec.pointerUp(pointerEvent(new Point(20, 0), "up", { type: "pen", pressure: 0.9 }));
    const free = ec.scene.visibleElements[0]!;
    expect(free.type).toBe("freedraw");
    if (free.type === "freedraw") {
      expect(free.points).toEqual([
        [0, 0],
        [10, 5],
        [20, 0],
      ]);
      expect(free.pressures).toEqual([0.3, 0.6, 0.9]);
    }
    expect(ec.activeTool).toBe("selection");
  });

  it("arrow gets the default end arrowhead", () => {
    const ec = makeEditor();
    ec.setTool("arrow");
    drag(ec, new Point(0, 0), new Point(80, 20));
    const arrow = ec.scene.visibleElements[0]!;
    if (arrow.type === "arrow") {
      expect(arrow.endArrowhead).toBe("arrow");
      expect(arrow.points[arrow.points.length - 1]).toEqual([80, 20]);
    }
  });

  it("eraser deletes and undoes", () => {
    const ec = makeEditor([rect("r", 0, 0, 100, 100)]);
    ec.setTool("eraser");
    ec.pointerDown(pointerEvent(new Point(50, 50), "down"));
    ec.pointerUp(pointerEvent(new Point(50, 50), "up"));
    expect(ec.scene.visibleElements.length).toBe(0);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(1);
  });

  it("hand tool neither creates nor selects", () => {
    const ec = makeEditor([rect("r", 0, 0, 100, 100)]);
    ec.setTool("hand");
    drag(ec, new Point(50, 50), new Point(80, 80));
    expect(ec.scene.visibleElements.length).toBe(1);
    expect(ec.selectedIDs.size).toBe(0);
  });

  it("redo after undo", () => {
    const ec = makeEditor();
    ec.setTool("ellipse");
    drag(ec, new Point(0, 0), new Point(40, 40));
    expect(ec.scene.visibleElements.length).toBe(1);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(0);
    expect(ec.redo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(1);
  });

  it("clears the selection", () => {
    const ec = makeEditor([rect("r", 0, 0, 50, 50)]);
    ec.selectAll();
    expect(ec.selectedIDs.size).toBeGreaterThan(0);
    ec.clearSelection();
    expect(ec.selectedIDs.size).toBe(0);
  });

  it("load resets history and selection", () => {
    const ec = makeEditor([rect("r", 0, 0, 50, 50)]);
    ec.selectAll();
    ec.load(new Scene([]));
    expect(ec.selectedIDs.size).toBe(0);
    expect(ec.scene.visibleElements.length).toBe(0);
  });
});
