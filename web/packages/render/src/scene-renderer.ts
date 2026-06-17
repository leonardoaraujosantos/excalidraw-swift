import { BoundingBox, cullVisible } from "@xs/geometry";
import type { ExcalidrawElement, Scene, TextElement } from "@xs/model";
import { viewBackgroundColor } from "@xs/model";
import { getStroke } from "perfect-freehand";
import { type PathSink, opsToPath } from "./drawable-path.js";
import { elementDrawable } from "./element-drawable.js";
import { buildRoughOptions } from "./rough-options.js";
import type { Viewport } from "./viewport.js";

/** The subset of `CanvasRenderingContext2D` the renderer uses. */
export interface RenderContext extends PathSink {
  save(): void;
  restore(): void;
  translate(x: number, y: number): void;
  scale(x: number, y: number): void;
  rotate(angle: number): void;
  closePath(): void;
  fill(): void;
  stroke(): void;
  fillRect(x: number, y: number, w: number, h: number): void;
  setLineDash(segments: number[]): void;
  fillText(text: string, x: number, y: number): void;
  fillStyle: string;
  strokeStyle: string;
  lineWidth: number;
  lineCap: CanvasLineCap;
  lineJoin: CanvasLineJoin;
  globalAlpha: number;
  font: string;
}

export type Theme = "light" | "dark";

export interface RenderOptions {
  viewport: Viewport;
  width: number;
  height: number;
  theme?: Theme;
  gridSize?: number;
}

function backgroundColor(scene: Scene, theme: Theme): string {
  return viewBackgroundColor(scene.appState) ?? (theme === "dark" ? "#121212" : "#ffffff");
}

function drawDrawable(ctx: RenderContext, el: ExcalidrawElement): void {
  const options = buildRoughOptions(el);
  const drawable = elementDrawable(el, options);
  if (drawable === null) return;
  const fill = drawable.options.fill;
  for (const set of drawable.sets) {
    opsToPath(set.ops, ctx);
    if (set.type === "fillPath") {
      if (fill) {
        ctx.fillStyle = fill;
        ctx.fill();
      }
    } else if (set.type === "fillSketch") {
      if (fill) {
        ctx.strokeStyle = fill;
        ctx.lineWidth =
          drawable.options.fillWeight && drawable.options.fillWeight > 0
            ? drawable.options.fillWeight
            : el.strokeWidth / 2;
        ctx.setLineDash([]);
        ctx.stroke();
      }
    } else {
      ctx.strokeStyle = el.strokeColor;
      ctx.lineWidth = el.strokeWidth;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.setLineDash(drawable.options.strokeLineDash ?? []);
      ctx.stroke();
    }
  }
}

function drawFreedraw(
  ctx: RenderContext,
  el: Extract<ExcalidrawElement, { type: "freedraw" }>,
): void {
  const inputs = el.points.map(
    (p, i) => [p[0], p[1], el.pressures[i] ?? 0.5] as [number, number, number],
  );
  const outline = getStroke(inputs, {
    size: Math.max(el.strokeWidth, 1) * 4.25,
    simulatePressure: el.simulatePressure,
  });
  if (outline.length < 3) return;
  ctx.beginPath();
  ctx.moveTo(outline[0]![0]!, outline[0]![1]!);
  for (let i = 1; i < outline.length; i++) ctx.lineTo(outline[i]![0]!, outline[i]![1]!);
  ctx.closePath();
  ctx.fillStyle = el.strokeColor;
  ctx.fill();
}

function drawText(ctx: RenderContext, el: TextElement): void {
  ctx.fillStyle = el.strokeColor;
  ctx.font = `${el.fontSize}px sans-serif`;
  const lineHeight = el.fontSize * el.lineHeight;
  const lines = el.text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (lines[i]!.length === 0) continue;
    ctx.fillText(lines[i]!, 0, lineHeight * i + el.fontSize * 0.8);
  }
}

function drawFrame(ctx: RenderContext, el: ExcalidrawElement): void {
  ctx.strokeStyle = "#999999";
  ctx.lineWidth = 1;
  ctx.setLineDash([]);
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(el.width, 0);
  ctx.lineTo(el.width, el.height);
  ctx.lineTo(0, el.height);
  ctx.closePath();
  ctx.stroke();
}

function visibleRegion(opts: RenderOptions): BoundingBox {
  const { viewport: v, width, height } = opts;
  return new BoundingBox(
    -v.scrollX,
    -v.scrollY,
    width / v.zoom - v.scrollX,
    height / v.zoom - v.scrollY,
  );
}

/**
 * Render a scene's static content (background, grid, elements) into a 2D
 * context. Assumes a y-down context. (parity: SceneRenderer.swift)
 */
export function renderScene(ctx: RenderContext, scene: Scene, opts: RenderOptions): void {
  const theme = opts.theme ?? "light";
  ctx.fillStyle = backgroundColor(scene, theme);
  ctx.fillRect(0, 0, opts.width, opts.height);

  ctx.save();
  ctx.scale(opts.viewport.zoom, opts.viewport.zoom);
  ctx.translate(opts.viewport.scrollX, opts.viewport.scrollY);

  const region = visibleRegion(opts);
  const elements = cullVisible(scene.visibleElements, region, 100);

  for (const el of elements) {
    ctx.save();
    ctx.globalAlpha = el.opacity / 100;
    ctx.translate(el.x, el.y);
    if (el.angle !== 0) {
      ctx.translate(el.width / 2, el.height / 2);
      ctx.rotate(el.angle);
      ctx.translate(-el.width / 2, -el.height / 2);
    }
    switch (el.type) {
      case "text":
        drawText(ctx, el);
        break;
      case "freedraw":
        drawFreedraw(ctx, el);
        break;
      case "frame":
      case "magicframe":
        drawFrame(ctx, el);
        break;
      case "image":
        break; // image bitmaps are drawn by the host
      default:
        drawDrawable(ctx, el);
        break;
    }
    ctx.restore();
  }
  ctx.restore();
}
