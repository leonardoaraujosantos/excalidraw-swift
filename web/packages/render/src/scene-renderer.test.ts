import { Scene } from "@xs/model";
import { describe, expect, it } from "vitest";
import { type RenderContext, renderScene } from "./scene-renderer.js";
import { rect, text } from "./test-helpers.js";
import { Viewport } from "./viewport.js";

/** A recording 2D context that counts the draw calls the renderer issues. */
class RecordingContext implements RenderContext {
  fillCount = 0;
  strokeCount = 0;
  fillRectCount = 0;
  fillTextCount = 0;
  pathOps = 0;
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
  moveTo() {
    this.pathOps++;
  }
  lineTo() {
    this.pathOps++;
  }
  bezierCurveTo() {
    this.pathOps++;
  }
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
  setLineDash() {}
  fillText() {
    this.fillTextCount++;
  }
}

const opts = (overrides = {}) => ({
  viewport: new Viewport(),
  width: 400,
  height: 300,
  ...overrides,
});

describe("scene renderer", () => {
  it("paints the background once", () => {
    const ctx = new RecordingContext();
    renderScene(ctx, new Scene([]), opts());
    expect(ctx.fillRectCount).toBe(1);
  });

  it("strokes a transparent rectangle's outline", () => {
    const ctx = new RecordingContext();
    renderScene(ctx, new Scene([rect({ x: 10, y: 10, w: 100, h: 60 })]), opts());
    expect(ctx.strokeCount).toBeGreaterThan(0);
    expect(ctx.pathOps).toBeGreaterThan(0);
  });

  it("fills a filled rectangle", () => {
    const ctx = new RecordingContext();
    renderScene(ctx, new Scene([rect({ x: 10, y: 10, w: 100, h: 60, bg: "#ff0000" })]), opts());
    expect(ctx.fillCount).toBeGreaterThan(0);
  });

  it("draws text via fillText", () => {
    const ctx = new RecordingContext();
    renderScene(ctx, new Scene([text("Hello", { x: 10, y: 10, w: 80, h: 25 })]), opts());
    expect(ctx.fillTextCount).toBe(1);
  });

  it("culls far off-screen elements", () => {
    const near = new RecordingContext();
    renderScene(near, new Scene([rect({ x: 10, y: 10, w: 100, h: 60 })]), opts());

    const far = new RecordingContext();
    renderScene(far, new Scene([rect({ x: 100_000, y: 100_000, w: 100, h: 60 })]), opts());

    expect(far.strokeCount).toBe(0);
    expect(near.strokeCount).toBeGreaterThan(0);
  });
});
