import type { Point } from "@cyberdynecorp/excalidraw-math";
import { type ExcalidrawElement, Scene, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { EditorController } from "./controller.js";
import { type PointerType, pointerEvent } from "./pointer-event.js";

/** A controller with deterministic id/seed providers, for tests. */
export function makeEditor(elements: ExcalidrawElement[] = []): EditorController {
  let idCount = 0;
  let seedCount = 0;
  return new EditorController(
    new Scene(elements),
    () => `e${++idCount}`,
    () => ++seedCount,
  );
}

export function rect(
  id: string,
  x: number,
  y: number,
  w: number,
  h: number,
  bg = "#ff0000",
): ExcalidrawElement {
  return {
    ...defaultBase(id, { x, y, width: w, height: h, backgroundColor: bg }),
    type: "rectangle",
  };
}

export function drag(
  ec: EditorController,
  from: Point,
  to: Point,
  type: PointerType = "mouse",
): void {
  ec.pointerDown(pointerEvent(from, "down", { type }));
  ec.pointerMove(pointerEvent(to, "move", { type }));
  ec.pointerUp(pointerEvent(to, "up", { type }));
}
