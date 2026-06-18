import type { Point } from "@cyberdynecorp/excalidraw-math";

/**
 * Axis-aligned bounding box in scene coordinates — the foundation for culling,
 * hit-testing early-outs, and multi-select bounds. (parity: BoundingBox.swift)
 */
export class BoundingBox {
  constructor(
    public minX: number,
    public minY: number,
    public maxX: number,
    public maxY: number,
  ) {}

  get width(): number {
    return this.maxX - this.minX;
  }

  get height(): number {
    return this.maxY - this.minY;
  }

  /** Smallest box enclosing a set of points, or `null` for an empty input. */
  static fromPoints(points: Point[]): BoundingBox | null {
    const first = points[0];
    if (first === undefined) return null;
    let minX = first.x;
    let minY = first.y;
    let maxX = first.x;
    let maxY = first.y;
    for (let i = 1; i < points.length; i++) {
      const p = points[i]!;
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x);
      maxY = Math.max(maxY, p.y);
    }
    return new BoundingBox(minX, minY, maxX, maxY);
  }

  contains(point: Point): boolean {
    return (
      point.x >= this.minX && point.x <= this.maxX && point.y >= this.minY && point.y <= this.maxY
    );
  }

  union(other: BoundingBox): BoundingBox {
    return new BoundingBox(
      Math.min(this.minX, other.minX),
      Math.min(this.minY, other.minY),
      Math.max(this.maxX, other.maxX),
      Math.max(this.maxY, other.maxY),
    );
  }
}
