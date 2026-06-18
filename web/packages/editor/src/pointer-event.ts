import type { Point } from "@cyberdynecorp/excalidraw-math";

export type PointerType = "mouse" | "pen" | "touch";
export type PointerPhase = "down" | "move" | "up";

/**
 * A single pointer sample, already in scene coordinates so the editor stays
 * independent of the viewport. (parity: PointerEvent.swift)
 */
export interface PointerEvent {
  scenePoint: Point;
  phase: PointerPhase;
  type: PointerType;
  pressure: number;
  shift: boolean;
  alt: boolean;
  toggleSelection: boolean;
}

export function pointerEvent(
  scenePoint: Point,
  phase: PointerPhase,
  opts: Partial<Omit<PointerEvent, "scenePoint" | "phase">> = {},
): PointerEvent {
  return {
    scenePoint,
    phase,
    type: opts.type ?? "mouse",
    pressure: opts.pressure ?? 0.5,
    shift: opts.shift ?? false,
    alt: opts.alt ?? false,
    toggleSelection: opts.toggleSelection ?? false,
  };
}
