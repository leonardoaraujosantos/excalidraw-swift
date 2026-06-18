import { Point } from "@cyberdynecorp/excalidraw-math";
import { describe, expect, it } from "vitest";
import { EditorStore } from "./editor-store.js";
import { TrailStore } from "./trail-store.js";

describe("TrailStore", () => {
  it("prunes points past the fade duration", () => {
    const trail = new TrailStore();
    trail.addLaser(new Point(0, 0), 0);
    trail.addLaser(new Point(10, 0), 0.1);
    expect(trail.visibleLaser(0.2).length).toBe(2);
    expect(trail.visibleLaser(1.0).length).toBe(0);
  });

  it("adding prunes stale history", () => {
    const trail = new TrailStore();
    trail.addLaser(new Point(0, 0), 0);
    trail.addLaser(new Point(1, 0), 5);
    expect(trail.laser.length).toBe(1);
  });

  it("laser and eraser trails are separate", () => {
    const trail = new TrailStore();
    trail.addLaser(new Point(0, 0), 0);
    trail.addEraser(new Point(5, 5), 0);
    expect(trail.laser.length).toBe(1);
    expect(trail.eraser.length).toBe(1);
    trail.clear();
    expect(trail.laser.length).toBe(0);
    expect(trail.eraser.length).toBe(0);
  });
});

describe("laser / eraser tools via the store", () => {
  it("laser records a trail and creates nothing", () => {
    const store = new EditorStore();
    store.selectTool("laser");
    store.pointer("down", new Point(10, 10), { now: 0 });
    store.pointer("move", new Point(60, 40), { now: 0.1 });
    store.pointer("up", new Point(60, 40), { now: 0.2 });
    expect(store.trail.laser.length).toBeGreaterThan(0);
    expect(store.scene.visibleElements.length).toBe(0);
    expect(store.activeTool).toBe("laser");
  });

  it("eraser records a trail and still erases", () => {
    const store = new EditorStore();
    store.setBackgroundColor("#a5d8ff");
    store.selectTool("rectangle");
    store.pointer("down", new Point(10, 10));
    store.pointer("move", new Point(80, 60));
    store.pointer("up", new Point(80, 60));
    expect(store.scene.visibleElements.length).toBe(1);

    store.selectTool("eraser");
    store.pointer("down", new Point(40, 30), { now: 0 });
    store.pointer("move", new Point(50, 40), { now: 0.05 });
    store.pointer("up", new Point(50, 40), { now: 0.1 });
    expect(store.trail.eraser.length).toBeGreaterThan(0);
    expect(store.scene.visibleElements.length).toBe(0);
  });
});
