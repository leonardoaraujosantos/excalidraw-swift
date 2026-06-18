import type { BoundingBox } from "@cyberdynecorp/excalidraw-geometry";
import type { Point } from "@cyberdynecorp/excalidraw-math";
import type { RenderContext } from "./scene-renderer.js";
import type { Viewport } from "./viewport.js";

const ACCENT = "#6b82f5"; // Excalidraw violet
const ACCENT_FILL = "rgba(107,130,245,0.08)";
const SNAP = "rgba(232,77,61,0.9)";
const WHITE = "#ffffff";
const TWO_PI = Math.PI * 2;

export interface TrailDot {
  position: Point;
  time: number;
}

export interface OverlayOptions {
  viewport: Viewport;
  width: number;
  height: number;
  selectionBounds?: BoundingBox | null;
  handles?: Point[];
  rotationHandle?: Point | null;
  selectionRect?: BoundingBox | null;
  snapLinesX?: number[];
  snapLinesY?: number[];
  linearPoints?: Point[];
  linearMidpoints?: Point[];
  cropFrame?: BoundingBox | null;
  cropHandles?: Point[];
  handleSizePx?: number;
  /** Current time (seconds) for fading the laser/eraser trails. */
  now?: number;
  laserDots?: TrailDot[];
  eraserDots?: TrailDot[];
  /** Remote collaborators' cursors (scene coords), drawn in each peer's colour. */
  remoteCursors?: { color: string; name: string; x: number; y: number }[];
}

const TRAIL_FADE = 0.7;

function drawTrail(
  ctx: RenderContext,
  dots: TrailDot[],
  now: number,
  color: string,
  width: number,
): void {
  if (dots.length < 2) return;
  ctx.strokeStyle = color;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = width;
  ctx.setLineDash([]);
  for (let i = 1; i < dots.length; i++) {
    const alpha = 1 - (now - dots[i]!.time) / TRAIL_FADE;
    if (alpha <= 0) continue;
    ctx.globalAlpha = alpha;
    ctx.beginPath();
    ctx.moveTo(dots[i - 1]!.position.x, dots[i - 1]!.position.y);
    ctx.lineTo(dots[i]!.position.x, dots[i]!.position.y);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

function squareHandle(ctx: RenderContext, p: Point, size: number, lineWidth: number): void {
  ctx.fillStyle = WHITE;
  ctx.fillRect(p.x - size / 2, p.y - size / 2, size, size);
  ctx.strokeStyle = ACCENT;
  ctx.lineWidth = lineWidth;
  ctx.strokeRect(p.x - size / 2, p.y - size / 2, size, size);
}

function circleHandle(ctx: RenderContext, p: Point, size: number, lineWidth: number): void {
  ctx.beginPath();
  ctx.arc(p.x, p.y, size / 2, 0, TWO_PI);
  ctx.fillStyle = WHITE;
  ctx.fill();
  ctx.strokeStyle = ACCENT;
  ctx.lineWidth = lineWidth;
  ctx.stroke();
}

/**
 * Draw the interactive overlay (selection box, transform handles, marquee, snap
 * guides, linear/crop edit handles) on top of the scene. (parity:
 * InteractiveRenderer.swift)
 */
export function renderOverlay(ctx: RenderContext, o: OverlayOptions): void {
  const v = o.viewport;
  ctx.save();
  ctx.scale(v.zoom, v.zoom);
  ctx.translate(v.scrollX, v.scrollY);

  const lineWidth = 1 / v.zoom;
  const handleSize = (o.handleSizePx ?? 8) / v.zoom;
  const snapLinesX = o.snapLinesX ?? [];
  const snapLinesY = o.snapLinesY ?? [];

  if (snapLinesX.length > 0 || snapLinesY.length > 0) {
    const topLeft = v.viewToScene({ x: 0, y: 0 } as Point);
    const bottomRight = v.viewToScene({ x: o.width, y: o.height } as Point);
    ctx.strokeStyle = SNAP;
    ctx.lineWidth = lineWidth;
    ctx.setLineDash([]);
    ctx.beginPath();
    for (const x of snapLinesX) {
      ctx.moveTo(x, topLeft.y);
      ctx.lineTo(x, bottomRight.y);
    }
    for (const y of snapLinesY) {
      ctx.moveTo(topLeft.x, y);
      ctx.lineTo(bottomRight.x, y);
    }
    ctx.stroke();
  }

  const rect = o.selectionRect ?? null;
  if (rect !== null) {
    ctx.strokeStyle = ACCENT;
    ctx.lineWidth = lineWidth;
    ctx.setLineDash([4 / v.zoom, 4 / v.zoom]);
    ctx.strokeRect(rect.minX, rect.minY, rect.width, rect.height);
    ctx.fillStyle = ACCENT_FILL;
    ctx.fillRect(rect.minX, rect.minY, rect.width, rect.height);
    ctx.setLineDash([]);
  }

  const bounds = o.selectionBounds ?? null;
  if (bounds !== null) {
    ctx.strokeStyle = ACCENT;
    ctx.lineWidth = lineWidth;
    ctx.setLineDash([]);
    ctx.strokeRect(bounds.minX, bounds.minY, bounds.width, bounds.height);
    const rotationHandle = o.rotationHandle ?? null;
    if (rotationHandle !== null) {
      ctx.beginPath();
      ctx.moveTo((bounds.minX + bounds.maxX) / 2, bounds.minY);
      ctx.lineTo(rotationHandle.x, rotationHandle.y);
      ctx.stroke();
      circleHandle(ctx, rotationHandle, handleSize, lineWidth);
    }
    for (const handle of o.handles ?? []) squareHandle(ctx, handle, handleSize, lineWidth);
  }

  const cropFrame = o.cropFrame ?? null;
  if (cropFrame !== null) {
    ctx.strokeStyle = ACCENT;
    ctx.lineWidth = lineWidth * 2;
    ctx.setLineDash([]);
    ctx.strokeRect(cropFrame.minX, cropFrame.minY, cropFrame.width, cropFrame.height);
    for (const handle of o.cropHandles ?? []) squareHandle(ctx, handle, handleSize, lineWidth);
  }

  for (const mid of o.linearMidpoints ?? []) circleHandle(ctx, mid, handleSize * 0.8, lineWidth);
  for (const p of o.linearPoints ?? []) {
    ctx.beginPath();
    ctx.arc(p.x, p.y, handleSize / 2, 0, TWO_PI);
    ctx.fillStyle = ACCENT;
    ctx.fill();
  }

  const now = o.now ?? 0;
  drawTrail(ctx, o.laserDots ?? [], now, "#ff2d2d", 4 / v.zoom);
  drawTrail(ctx, o.eraserDots ?? [], now, "#9aa0a6", 10 / v.zoom);

  for (const cursor of o.remoteCursors ?? []) {
    const s = 1 / v.zoom;
    // A small arrowhead pointing up-left at the cursor position.
    ctx.beginPath();
    ctx.moveTo(cursor.x, cursor.y);
    ctx.lineTo(cursor.x + 12 * s, cursor.y + 4 * s);
    ctx.lineTo(cursor.x + 4 * s, cursor.y + 12 * s);
    ctx.closePath();
    ctx.fillStyle = cursor.color;
    ctx.fill();
    // Name tag.
    ctx.font = `${12 * s}px sans-serif`;
    ctx.fillText(cursor.name, cursor.x + 14 * s, cursor.y + 20 * s);
  }

  ctx.restore();
}
