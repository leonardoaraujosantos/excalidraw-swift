import { Point } from "@cyberdynecorp/excalidraw-math";

/** The allowed zoom range. */
export const ZOOM_RANGE = { min: 0.1, max: 30 } as const;

/**
 * Maps scene coordinates to view coordinates given the current pan/zoom — the
 * single source of truth for the canvas transform. (parity: Viewport in
 * SceneRenderer.swift)
 */
export class Viewport {
  constructor(
    public scrollX = 0,
    public scrollY = 0,
    public zoom = 1,
  ) {}

  sceneToView(point: Point): Point {
    return new Point((point.x + this.scrollX) * this.zoom, (point.y + this.scrollY) * this.zoom);
  }

  viewToScene(point: Point): Point {
    return new Point(point.x / this.zoom - this.scrollX, point.y / this.zoom - this.scrollY);
  }
}
