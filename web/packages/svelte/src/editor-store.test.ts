import { Point } from "@xs/math";
import { Viewport } from "@xs/render";
import { describe, expect, it } from "vitest";
import { EditorStore } from "./editor-store.js";

/** A recording 2D context that counts draw calls. */
class RecordingContext {
  fillCount = 0;
  strokeCount = 0;
  fillRectCount = 0;
  strokeRectCount = 0;
  arcCount = 0;
  fillTextCount = 0;
  fillStyle = "";
  strokeStyle = "";
  lineWidth = 1;
  lineCap: CanvasLineCap = "butt";
  lineJoin: CanvasLineJoin = "miter";
  globalAlpha = 1;
  font = "";
  save() {}
  restore() {}
  translate() {}
  scale() {}
  rotate() {}
  beginPath() {}
  moveTo() {}
  lineTo() {}
  bezierCurveTo() {}
  closePath() {}
  fill() {
    this.fillCount++;
  }
  stroke() {
    this.strokeCount++;
  }
  fillRect() {
    this.fillRectCount++;
  }
  strokeRect() {
    this.strokeRectCount++;
  }
  arc() {
    this.arcCount++;
  }
  setLineDash() {}
  fillText() {
    this.fillTextCount++;
  }
}

describe("EditorStore", () => {
  it("forwards a pointer drag and creates an element, bumping the revision", () => {
    const store = new EditorStore();
    store.selectTool("rectangle");
    const before = store.revision;
    store.pointer("down", new Point(10, 10));
    store.pointer("move", new Point(60, 40));
    store.pointer("up", new Point(60, 40));
    expect(store.scene.visibleElements.length).toBe(1);
    expect(store.scene.visibleElements[0]!.type).toBe("rectangle");
    expect(store.revision).toBeGreaterThan(before);
    expect(store.activeTool).toBe("selection");
  });

  it("converts view to scene coordinates with the viewport zoom", () => {
    const store = new EditorStore(undefined, new Viewport(0, 0, 2));
    store.selectTool("rectangle");
    store.pointer("down", new Point(20, 20));
    store.pointer("move", new Point(40, 40));
    store.pointer("up", new Point(40, 40));
    const el = store.scene.visibleElements[0]!;
    expect(el.x).toBeCloseTo(10, 6); // view 20 / zoom 2
    expect(el.y).toBeCloseTo(10, 6);
  });

  it("panZoom scales the scroll by the zoom", () => {
    const store = new EditorStore(undefined, new Viewport(0, 0, 2));
    store.panZoom(10, 20, 1);
    expect(store.viewport.scrollX).toBeCloseTo(5, 6);
    expect(store.viewport.scrollY).toBeCloseTo(10, 6);
  });

  it("zoom in / out / reset and percent", () => {
    const store = new EditorStore();
    store.zoomIn();
    expect(store.viewport.zoom).toBeCloseTo(1.2, 6);
    expect(store.zoomPercent).toBe(120);
    store.resetZoom();
    expect(store.viewport.zoom).toBe(1);
    store.zoomOut();
    expect(store.viewport.zoom).toBeCloseTo(1 / 1.2, 6);
  });

  it("theme toggles", () => {
    const store = new EditorStore();
    expect(store.theme).toBe("light");
    store.toggleTheme();
    expect(store.theme).toBe("dark");
  });

  it("style setters apply to the selection", () => {
    const store = new EditorStore();
    store.selectTool("rectangle");
    store.pointer("down", new Point(0, 0));
    store.pointer("move", new Point(50, 50));
    store.pointer("up", new Point(50, 50));
    store.setStrokeColor("#e03131");
    expect(store.scene.visibleElements[0]!.strokeColor).toBe("#e03131");
  });

  it("selection stats reflect the selection size", () => {
    const store = new EditorStore();
    expect(store.selectionStats).toBeNull();
    store.selectTool("rectangle");
    store.pointer("down", new Point(0, 0));
    store.pointer("move", new Point(120, 80));
    store.pointer("up", new Point(120, 80));
    expect(store.selectionStats).toBe("120 × 80");
  });

  it("renders the scene to a 2D context", () => {
    const store = new EditorStore();
    store.selectTool("rectangle");
    store.pointer("down", new Point(10, 10));
    store.pointer("move", new Point(110, 70));
    store.pointer("up", new Point(110, 70));
    const ctx = new RecordingContext();
    store.render(ctx, 400, 300);
    expect(ctx.fillRectCount).toBe(1); // background
    expect(ctx.strokeCount).toBeGreaterThan(0); // the rectangle outline
  });

  it("draws the interactive overlay for a selection", () => {
    const store = new EditorStore();
    store.selectTool("rectangle");
    store.pointer("down", new Point(0, 0));
    store.pointer("move", new Point(100, 100));
    store.pointer("up", new Point(100, 100)); // rectangle stays selected
    const ctx = new RecordingContext();
    store.renderOverlay(ctx, 400, 300);
    expect(ctx.strokeRectCount).toBeGreaterThanOrEqual(5); // selection box + 8 handles
    expect(ctx.fillRectCount).toBe(8); // white handle squares
  });

  it("exports SVG and round-trips a document", () => {
    const store = new EditorStore();
    store.selectTool("ellipse");
    store.pointer("down", new Point(0, 0));
    store.pointer("move", new Point(60, 40));
    store.pointer("up", new Point(60, 40));
    expect(store.exportSvg()).toContain("<svg");
    const json = store.documentJSON();
    const reopened = new EditorStore();
    reopened.loadDocument(json);
    expect(reopened.scene.visibleElements.length).toBe(1);
  });

  it("undo/redo through the store", () => {
    const store = new EditorStore();
    store.selectTool("rectangle");
    store.pointer("down", new Point(0, 0));
    store.pointer("move", new Point(50, 50));
    store.pointer("up", new Point(50, 50));
    expect(store.canUndo).toBe(true);
    store.undo();
    expect(store.scene.visibleElements.length).toBe(0);
    store.redo();
    expect(store.scene.visibleElements.length).toBe(1);
  });

  it("generators place elements at the viewport centre", () => {
    const store = new EditorStore();
    store.insertTable(2, 2);
    expect(store.scene.visibleElements.length).toBe(8); // 4 cells + 4 labels
    store.insertStickyNote();
    expect(store.scene.visibleElements.some((e) => e.backgroundColor === "#ffec99")).toBe(true);
  });

  it("inserting a sticky note begins editing its bound text (regression)", () => {
    const store = new EditorStore();
    store.insertStickyNote();
    expect(store.editingText).not.toBeNull();
    const note = store.scene.visibleElements.find((e) => e.type === "rectangle");
    const boundTextId = note?.boundElements?.find((b) => b.type === "text")?.id;
    expect(boundTextId).toBeDefined();
    expect(store.editingText?.id).toBe(boundTextId);

    // Typing into the editor and committing stores the text on the bound element.
    store.setEditingText("hello");
    store.commitText();
    expect(store.editingText).toBeNull();
    const label = store.scene.element(boundTextId!);
    expect(label?.type === "text" && label.text).toBe("hello");
  });

  it("double-clicking a sticky note re-opens its text editor (regression)", () => {
    const store = new EditorStore();
    store.insertStickyNote();
    const note = store.scene.visibleElements.find((e) => e.type === "rectangle")!;
    store.setEditingText("note");
    store.commitText();
    expect(store.editingText).toBeNull();

    // Double-click on the note's centre (default viewport: scene == view).
    const center = new Point(note.x + note.width / 2, note.y + note.height / 2);
    expect(store.editBoundTextAt(center)).toBe(true);
    expect(store.editingText?.value).toBe("note");

    // Double-click on empty space does nothing.
    expect(store.editBoundTextAt(new Point(5000, 5000))).toBe(false);
  });

  it("double-clicking a line enters point (spline) editing (regression)", () => {
    const store = new EditorStore();
    store.selectTool("line");
    // draw a line from (100,100) to (300,160)
    store.pointer("down", new Point(100, 100));
    store.pointer("move", new Point(300, 160));
    store.pointer("up", new Point(300, 160));
    const line = store.scene.visibleElements.find((e) => e.type === "line")!;
    expect(store.isLinearEditing).toBe(false);

    store.selectTool("selection");
    // double-click on a point along the line enters vertex editing
    store.doubleClickAt(new Point(line.x, line.y));
    expect(store.isLinearEditing).toBe(true);
  });

  it("changing the fill pattern updates the selection and the current item (regression)", () => {
    const store = new EditorStore();
    store.selectTool("rectangle");
    store.pointer("down", new Point(20, 20));
    store.pointer("move", new Point(120, 90));
    store.pointer("up", new Point(120, 90));
    store.controller.selectAll();

    store.setFillStyle("cross-hatch");
    const rect = store.scene.visibleElements.find((e) => e.type === "rectangle")!;
    expect(rect.fillStyle).toBe("cross-hatch");
    expect(store.controller.currentItem.fillStyle).toBe("cross-hatch");
  });
});
