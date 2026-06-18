import type { Point } from "@cyberdynecorp/excalidraw-math";

export interface TrailDot {
  position: Point;
  time: number;
}

/**
 * Ephemeral fading trails for the laser pointer and the eraser. Points are
 * recorded in scene coordinates with a timestamp (seconds); the overlay renders
 * them with an age-based opacity and drops anything past `fadeDuration`.
 * (parity: TrailStore.swift)
 */
export class TrailStore {
  /** How long (seconds) a trail point takes to fully fade out. */
  static readonly fadeDuration = 0.7;

  laser: TrailDot[] = [];
  eraser: TrailDot[] = [];

  private prune(points: TrailDot[], now: number): TrailDot[] {
    return points.filter((d) => now - d.time < TrailStore.fadeDuration);
  }

  addLaser(position: Point, now: number): void {
    this.laser = this.prune(this.laser, now);
    this.laser.push({ position, time: now });
  }

  addEraser(position: Point, now: number): void {
    this.eraser = this.prune(this.eraser, now);
    this.eraser.push({ position, time: now });
  }

  clear(): void {
    this.laser = [];
    this.eraser = [];
  }

  visibleLaser(now: number): TrailDot[] {
    return this.prune(this.laser, now);
  }

  visibleEraser(now: number): TrailDot[] {
    return this.prune(this.eraser, now);
  }
}
