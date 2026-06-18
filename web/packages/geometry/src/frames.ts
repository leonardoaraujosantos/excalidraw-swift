import { Point } from "@cyberdynecorp/excalidraw-math";
import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";
import { bounds } from "./element-geometry.js";

/** Frame membership helpers (`frame.ts`, simplified). (parity: Frames.swift) */
export function isFrame(el: ExcalidrawElement): boolean {
  return el.type === "frame" || el.type === "magicframe";
}

/** The id of the topmost frame containing `el`'s centre, or `null`. */
export function frameContaining(
  el: ExcalidrawElement,
  elements: ExcalidrawElement[],
): string | null {
  if (isFrame(el)) return null;
  const b = bounds(el);
  const center = new Point((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2);
  for (let i = elements.length - 1; i >= 0; i--) {
    const frame = elements[i]!;
    if (isFrame(frame) && !frame.isDeleted && bounds(frame).contains(center)) {
      return frame.id;
    }
  }
  return null;
}

/** Non-deleted elements that belong to the given frame. */
export function frameChildren(frameId: string, elements: ExcalidrawElement[]): ExcalidrawElement[] {
  return elements.filter((el) => !el.isDeleted && el.frameId === frameId);
}
