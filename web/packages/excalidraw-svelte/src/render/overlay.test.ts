import { describe, expect, it } from "vitest";
import { BoundingBox } from "../geometry/index.js";
import { Point } from "../math/index.js";
import { renderOverlay } from "./overlay.js";
import type { RenderContext } from "./scene-renderer.js";
import { Viewport } from "./viewport.js";

class RecordingContext implements RenderContext {
  fillCount = 0;
  strokeCount = 0;
  fillRectCount = 0;
  strokeRectCount = 0;
  arcCount = 0;
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
  fillText() {}
  drawImage() {}
}

const opts = (over: Partial<Parameters<typeof renderOverlay>[1]> = {}) => ({
  viewport: new Viewport(),
  width: 400,
  height: 300,
  ...over,
});

describe("interactive overlay", () => {
  it("draws nothing for an empty overlay", () => {
    const ctx = new RecordingContext();
    renderOverlay(ctx, opts());
    expect(ctx.strokeRectCount).toBe(0);
    expect(ctx.fillRectCount).toBe(0);
  });

  it("draws the selection box and square handles", () => {
    const ctx = new RecordingContext();
    renderOverlay(
      ctx,
      opts({
        selectionBounds: new BoundingBox(0, 0, 100, 100),
        handles: [new Point(0, 0), new Point(100, 0), new Point(100, 100), new Point(0, 100)],
        rotationHandle: new Point(50, -30),
      }),
    );
    expect(ctx.strokeRectCount).toBeGreaterThanOrEqual(5); // box + 4 handles
    expect(ctx.fillRectCount).toBe(4); // white handle fills
    expect(ctx.arcCount).toBe(1); // rotation circle
  });

  it("draws the marquee with a dashed border and fill", () => {
    const ctx = new RecordingContext();
    renderOverlay(ctx, opts({ selectionRect: new BoundingBox(10, 10, 90, 60) }));
    expect(ctx.strokeRectCount).toBe(1);
    expect(ctx.fillRectCount).toBe(1);
  });

  it("draws linear-edit point and midpoint handles", () => {
    const ctx = new RecordingContext();
    renderOverlay(
      ctx,
      opts({
        linearPoints: [new Point(0, 0), new Point(50, 0)],
        linearMidpoints: [new Point(25, 0)],
      }),
    );
    expect(ctx.arcCount).toBe(3); // 1 midpoint circle + 2 point dots
  });

  it("draws snap guide lines", () => {
    const ctx = new RecordingContext();
    renderOverlay(ctx, opts({ snapLinesX: [50], snapLinesY: [80] }));
    expect(ctx.strokeCount).toBeGreaterThan(0);
  });
});
