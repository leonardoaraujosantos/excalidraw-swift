import { isPathALoop } from "@cyberdynecorp/excalidraw-geometry";
import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";
import type { Options } from "roughjs/bin/core";

const CARTOONIST_ROUGHNESS = 2;

function isTransparent(color: string): boolean {
  if (color === "transparent" || color.length === 0) return true;
  return color.length === 9 && color.startsWith("#") && color.endsWith("00");
}

/** Reduce roughness for small shapes so the sketch doesn't look noisy. */
export function adjustRoughness(el: ExcalidrawElement): number {
  const roughness = el.roughness;
  const maxSize = Math.max(el.width, el.height);
  const minSize = Math.min(el.width, el.height);
  if (minSize >= 20 && maxSize >= 50) return roughness;
  return Math.min(roughness / 2, 2.5);
}

/**
 * Builds rough.js options for an element (`generateRoughOptions`). (parity:
 * RoughOptionsBuilder.swift)
 */
export function buildRoughOptions(el: ExcalidrawElement, continuousPath = false): Options {
  const solid = el.strokeStyle === "solid";
  const o: Options = {
    seed: el.seed,
    disableMultiStroke: !solid,
    strokeWidth: solid ? el.strokeWidth : el.strokeWidth + 0.5,
    fillWeight: el.strokeWidth / 2,
    hachureGap: el.strokeWidth * 4,
    roughness: adjustRoughness(el),
    preserveVertices: continuousPath || el.roughness < CARTOONIST_ROUGHNESS,
  };

  if (el.strokeStyle === "dashed") o.strokeLineDash = [8, 8 + el.strokeWidth];
  else if (el.strokeStyle === "dotted") o.strokeLineDash = [1.5, 6 + el.strokeWidth];

  const applyFill = (): void => {
    o.fillStyle = el.fillStyle;
    if (!isTransparent(el.backgroundColor)) o.fill = el.backgroundColor;
  };

  switch (el.type) {
    case "rectangle":
    case "iframe":
    case "embeddable":
    case "diamond":
    case "ellipse":
      applyFill();
      if (el.type === "ellipse") o.curveFitting = 1;
      break;
    case "line":
      if (el.polygon || isPathALoop(el.points)) applyFill();
      break;
    case "freedraw":
      if (isPathALoop(el.points)) applyFill();
      break;
    default:
      break;
  }
  return o;
}
