import { getStroke } from "perfect-freehand";
import { BoundingBox, cullVisible } from "../geometry/index.js";
import type {
  Arrowhead,
  ExcalidrawElement,
  LocalPoint,
  Scene,
  TextElement,
} from "../model/index.js";
import { viewBackgroundColor } from "../model/index.js";
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
  strokeRect(x: number, y: number, w: number, h: number): void;
  arc(x: number, y: number, radius: number, startAngle: number, endAngle: number): void;
  setLineDash(segments: number[]): void;
  fillText(text: string, x: number, y: number): void;
  drawImage(image: CanvasImageSource, dx: number, dy: number, dw: number, dh: number): void;
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
  /** Resolve a loaded bitmap for an image element's `fileId`. The host owns the
   * (async) image cache and redraws once a bitmap finishes loading; images whose
   * bitmap isn't ready yet (or off a non-DOM renderer) are skipped this frame. */
  images?: (fileId: string) => CanvasImageSource | null;
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

/**
 * Draw an arrowhead at `tip`, oriented along the segment from `prev` to `tip`.
 * Triangle/diamond heads are filled; everything else is an open "V" stroke.
 * (parity: SceneRenderer.drawArrowhead)
 */
function drawArrowhead(
  ctx: RenderContext,
  tip: LocalPoint,
  prev: LocalPoint,
  head: Arrowhead,
  color: string,
  strokeWidth: number,
): void {
  const dx = tip[0] - prev[0];
  const dy = tip[1] - prev[1];
  const len = Math.hypot(dx, dy);
  if (len === 0) return;
  const ux = dx / len; // unit vector pointing toward the tip
  const uy = dy / len;
  const size = Math.min(20, len * 0.5) + strokeWidth;
  const angle = (25 * Math.PI) / 180;
  // Two barbs: rotate the reverse direction by ±angle.
  const bx = -ux;
  const by = -uy;
  const p1x = tip[0] + (bx * Math.cos(angle) - by * Math.sin(angle)) * size;
  const p1y = tip[1] + (bx * Math.sin(angle) + by * Math.cos(angle)) * size;
  const p2x = tip[0] + (bx * Math.cos(-angle) - by * Math.sin(-angle)) * size;
  const p2y = tip[1] + (bx * Math.sin(-angle) + by * Math.cos(-angle)) * size;

  const filled = head === "triangle" || head === "diamond";
  ctx.beginPath();
  ctx.moveTo(p1x, p1y);
  ctx.lineTo(tip[0], tip[1]);
  ctx.lineTo(p2x, p2y);
  if (filled) {
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  } else {
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineCap = "round";
    ctx.setLineDash([]);
    ctx.stroke();
  }
}

/** Draw the start/end arrowheads of an arrow element. (parity: SceneRenderer.drawArrowheads) */
function drawArrowheads(
  ctx: RenderContext,
  el: Extract<ExcalidrawElement, { type: "arrow" }>,
): void {
  const pts = el.points;
  if (pts.length < 2) return;
  if (el.endArrowhead !== null) {
    const tip = pts[pts.length - 1]!;
    const prev = pts[pts.length - 2]!;
    drawArrowhead(ctx, tip, prev, el.endArrowhead, el.strokeColor, el.strokeWidth);
  }
  if (el.startArrowhead !== null) {
    drawArrowhead(ctx, pts[0]!, pts[1]!, el.startArrowhead, el.strokeColor, el.strokeWidth);
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

/**
 * Approximate rendered size of a text block (widest line × total height), using
 * the same `fontSize · 0.6` advance the editor uses when it sizes text. Mirrors
 * Swift's `TextLayout.measure`, which is what bound-text centering keys on — the
 * stored `width`/`height` can be a container cell size (e.g. a table/Mermaid
 * node), not the glyph extent. (parity: TextLayout.measure)
 */
function measureText(el: TextElement): { width: number; height: number } {
  const lines = el.text.split("\n");
  const longest = lines.reduce((m, l) => Math.max(m, l.length), 0);
  return {
    width: longest * el.fontSize * 0.6,
    height: Math.max(1, lines.length) * el.fontSize * el.lineHeight,
  };
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
      case "text": {
        // Centre text bound to a container (e.g. a sticky note, table cell, or
        // Mermaid node) within it, by the *measured* glyph size — the stored
        // width may be the full cell, which would otherwise left-align the label.
        const container = el.containerId !== null ? scene.element(el.containerId) : undefined;
        if (container !== undefined) {
          const m = measureText(el);
          const ox = container.x + container.width / 2 - m.width / 2;
          const oy = container.y + container.height / 2 - m.height / 2;
          ctx.translate(ox - el.x, oy - el.y);
        }
        drawText(ctx, el);
        break;
      }
      case "freedraw":
        drawFreedraw(ctx, el);
        break;
      case "frame":
      case "magicframe":
        drawFrame(ctx, el);
        break;
      case "image": {
        // The ctx is already translated to (el.x, el.y) and rotated. Draw the
        // host-resolved bitmap into the element's box, honouring scale (flip).
        const bitmap = el.fileId !== null ? (opts.images?.(el.fileId) ?? null) : null;
        if (bitmap !== null) {
          const [sx, sy] = el.scale ?? [1, 1];
          if (sx < 0 || sy < 0) {
            ctx.translate(sx < 0 ? el.width : 0, sy < 0 ? el.height : 0);
            ctx.scale(sx < 0 ? -1 : 1, sy < 0 ? -1 : 1);
          }
          ctx.drawImage(bitmap, 0, 0, el.width, el.height);
        }
        break;
      }
      case "arrow":
        drawDrawable(ctx, el);
        drawArrowheads(ctx, el);
        break;
      default:
        drawDrawable(ctx, el);
        break;
    }
    ctx.restore();
  }
  ctx.restore();
}
