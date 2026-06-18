import { Point } from "@cyberdynecorp/excalidraw-math";
import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { pointerEvent } from "./pointer-event.js";
import { makeEditor } from "./test-helpers.js";

function rect(id: string, x: number, y: number, w = 20, h = 20): ExcalidrawElement {
  return { ...defaultBase(id, { x, y, width: w, height: h }), type: "rectangle" };
}

function boxSelect(ec: ReturnType<typeof makeEditor>, from: Point, to: Point): void {
  ec.pointerDown(pointerEvent(from, "down"));
  ec.pointerMove(pointerEvent(to, "move"));
  ec.pointerUp(pointerEvent(to, "up"));
}

describe("editor actions", () => {
  it("group and ungroup", () => {
    const ec = makeEditor([rect("a", 0, 0), rect("b", 50, 0)]);
    ec.selectAll();
    ec.group();
    const groupIds = ec.scene.element("a")?.groupIds;
    expect(groupIds?.length).toBe(1);
    expect(ec.scene.element("b")?.groupIds).toEqual(groupIds);
    ec.ungroup();
    expect(ec.scene.element("a")?.groupIds).toEqual([]);
  });

  it("duplicate offsets and selects the copies", () => {
    const ec = makeEditor([rect("a", 0, 0)]);
    ec.selectAll();
    ec.duplicate();
    expect(ec.scene.visibleElements.length).toBe(2);
    expect(ec.selectedIDs.has("a")).toBe(false);
    const copy = ec.selectedElements[0]!;
    expect(copy.x).toBe(10);
    expect(copy.y).toBe(10);
  });

  it("lock and unlock", () => {
    const ec = makeEditor([rect("a", 0, 0)]);
    ec.selectAll();
    ec.setLocked(true);
    expect(ec.scene.element("a")?.locked).toBe(true);
    ec.setLocked(false);
    expect(ec.scene.element("a")?.locked).toBe(false);
  });

  it("z-order", () => {
    const ec = makeEditor([rect("a", 0, 0), rect("b", 40, 0), rect("c", 80, 0)]);
    boxSelect(ec, new Point(-5, -5), new Point(25, 25));
    expect([...ec.selectedIDs]).toEqual(["a"]);
    ec.reorder("front");
    expect(ec.scene.elements.map((e) => e.id)).toEqual(["b", "c", "a"]);
    ec.reorder("backward");
    expect(ec.scene.elements.map((e) => e.id)).toEqual(["b", "a", "c"]);
    ec.reorder("back");
    expect(ec.scene.elements.map((e) => e.id)).toEqual(["a", "b", "c"]);
    ec.reorder("forward");
    expect(ec.scene.elements.map((e) => e.id)).toEqual(["b", "a", "c"]);
  });

  it("align", () => {
    const ec = makeEditor([rect("a", 0, 0), rect("b", 100, 50)]);
    ec.selectAll();
    ec.align("left");
    expect(ec.scene.element("a")?.x).toBe(0);
    expect(ec.scene.element("b")?.x).toBe(0);
    ec.align("top");
    expect(ec.scene.element("b")?.y).toBe(0);
  });

  it("flip horizontal mirrors positions", () => {
    const ec = makeEditor([rect("a", 0, 0, 20, 20), rect("b", 100, 0, 20, 20)]);
    ec.selectAll();
    ec.flip(true);
    expect(ec.scene.element("a")?.x).toBe(100);
    expect(ec.scene.element("b")?.x).toBe(0);
  });

  it("actions are undoable", () => {
    const ec = makeEditor([rect("a", 0, 0)]);
    ec.selectAll();
    ec.setLocked(true);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.element("a")?.locked).toBe(false);
  });
});
