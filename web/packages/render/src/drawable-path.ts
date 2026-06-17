import type { Op, OpSet } from "roughjs/bin/core";

function fmt(value: number): string {
  return value.toFixed(2);
}

/** Serialize a rough.js op set to an SVG path `d` string. */
export function opsToSvgPath(ops: Op[]): string {
  let d = "";
  for (const op of ops) {
    const p = op.data;
    switch (op.op) {
      case "move":
        d += `M ${fmt(p[0]!)} ${fmt(p[1]!)} `;
        break;
      case "lineTo":
        d += `L ${fmt(p[0]!)} ${fmt(p[1]!)} `;
        break;
      case "bcurveTo":
        d += `C ${fmt(p[0]!)} ${fmt(p[1]!)} ${fmt(p[2]!)} ${fmt(p[3]!)} ${fmt(p[4]!)} ${fmt(p[5]!)} `;
        break;
    }
  }
  return d.trim();
}

/** A minimal 2D path sink — the subset of `CanvasRenderingContext2D` we use. */
export interface PathSink {
  beginPath(): void;
  moveTo(x: number, y: number): void;
  lineTo(x: number, y: number): void;
  bezierCurveTo(c1x: number, c1y: number, c2x: number, c2y: number, x: number, y: number): void;
}

/** Replay a rough.js op set into a canvas-style path sink. */
export function opsToPath(ops: Op[], sink: PathSink): void {
  sink.beginPath();
  for (const op of ops) {
    const p = op.data;
    switch (op.op) {
      case "move":
        sink.moveTo(p[0]!, p[1]!);
        break;
      case "lineTo":
        sink.lineTo(p[0]!, p[1]!);
        break;
      case "bcurveTo":
        sink.bezierCurveTo(p[0]!, p[1]!, p[2]!, p[3]!, p[4]!, p[5]!);
        break;
    }
  }
}

export type { OpSet };
