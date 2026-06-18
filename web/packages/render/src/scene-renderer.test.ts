import {
  type ExcalidrawElement,
  Scene,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { type RenderContext, renderScene } from "./scene-renderer.js";
import { arrow, rect, text } from "./test-helpers.js";
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
  // Track the accumulated transform so tests can assert *where* text lands.
  private tx = 0;
  private ty = 0;
  private stack: [number, number][] = [];
  lastTextOrigin: [number, number] | null = null;

  save() {
    this.stack.push([this.tx, this.ty]);
  }
  restore() {
    const top = this.stack.pop();
    if (top !== undefined) [this.tx, this.ty] = top;
  }
  translate(x: number, y: number) {
    this.tx += x;
    this.ty += y;
  }
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
  strokeRect() {}
  arc() {}
  setLineDash() {}
  fillText(_text: string, x: number, y: number) {
    this.fillTextCount++;
    this.lastTextOrigin = [this.tx + x, this.ty + y];
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

  it("draws an open arrowhead on top of the arrow's line (regression)", () => {
    const plain = new RecordingContext();
    renderScene(
      plain,
      new Scene([
        arrow(
          [
            [0, 0],
            [100, 0],
          ],
          { x: 50, y: 50 },
        ),
      ]),
      opts(),
    );

    const headed = new RecordingContext();
    const withHead = {
      ...arrow(
        [
          [0, 0],
          [100, 0],
        ],
        { x: 50, y: 50 },
      ),
      endArrowhead: "arrow",
    } as ExcalidrawElement;
    renderScene(headed, new Scene([withHead]), opts());

    // The "V" head adds an extra stroked path (move + 2 lines) over the bare line.
    expect(headed.strokeCount).toBeGreaterThan(plain.strokeCount);
    expect(headed.pathOps).toBeGreaterThan(plain.pathOps);
  });

  it("fills a triangle arrowhead (regression)", () => {
    const ctx = new RecordingContext();
    const tri = {
      ...arrow(
        [
          [0, 0],
          [100, 0],
        ],
        { x: 50, y: 50 },
      ),
      endArrowhead: "triangle",
    } as ExcalidrawElement;
    renderScene(ctx, new Scene([tri]), opts());
    expect(ctx.fillCount).toBeGreaterThan(0);
  });

  it("centres container-bound text inside its container (regression)", () => {
    const container: ExcalidrawElement = {
      ...defaultBase("cont", { x: 20, y: 20, width: 160, height: 160 }),
      type: "rectangle",
    };
    const label: ExcalidrawElement = {
      // width 140 mimics a table/Mermaid cell whose stored width is the cell,
      // not the glyph — centring must use the measured text width, not this.
      ...defaultBase("txt", { x: 20, y: 100, width: 140, height: 20 }),
      type: "text",
      ...defaultTextProps({ text: "Hi", originalText: "Hi", containerId: "cont" }),
    };
    const ctx = new RecordingContext();
    renderScene(ctx, new Scene([container, label]), opts());

    // x origin == container.midX - measuredWidth/2 == 100 - (2·20·0.6)/2 == 88,
    // independent of the text's stored width (140) and x (20): re-centred by glyphs.
    expect(ctx.lastTextOrigin).not.toBeNull();
    expect(ctx.lastTextOrigin![0]).toBeCloseTo(88, 5);
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
