import { commonBounds } from "@xs/geometry";
import type { ExcalidrawElement, Scene, TextElement } from "@xs/model";
import { viewBackgroundColor } from "@xs/model";
import { getStroke } from "perfect-freehand";
import { opsToSvgPath } from "./drawable-path.js";
import { elementDrawable } from "./element-drawable.js";
import { buildRoughOptions } from "./rough-options.js";

function fmt(value: number): string {
  return value.toFixed(2);
}

function escapeXml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function emptySvg(): string {
  return '<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0" viewBox="0 0 0 0"></svg>';
}

function drawableBody(el: ExcalidrawElement): string {
  const options = buildRoughOptions(el);
  const drawable = elementDrawable(el, options);
  if (drawable === null) return "";
  const stroke = el.strokeColor;
  const fill = drawable.options.fill;
  let out = "";
  for (const set of drawable.sets) {
    const d = opsToSvgPath(set.ops);
    if (set.type === "fillPath") {
      if (fill) out += `<path d="${d}" fill="${escapeXml(fill)}" stroke="none"/>`;
    } else if (set.type === "fillSketch") {
      if (fill) {
        const weight =
          drawable.options.fillWeight && drawable.options.fillWeight > 0
            ? drawable.options.fillWeight
            : el.strokeWidth / 2;
        out += `<path d="${d}" fill="none" stroke="${escapeXml(fill)}" stroke-width="${fmt(weight)}"/>`;
      }
    } else {
      const dash = drawable.options.strokeLineDash
        ? ` stroke-dasharray="${drawable.options.strokeLineDash.map(fmt).join(",")}"`
        : "";
      out += `<path d="${d}" fill="none" stroke="${escapeXml(stroke)}" stroke-width="${fmt(el.strokeWidth)}" stroke-linecap="round"${dash}/>`;
    }
  }
  return out;
}

function freedrawBody(el: Extract<ExcalidrawElement, { type: "freedraw" }>): string {
  const inputs = el.points.map(
    (p, i) => [p[0], p[1], el.pressures[i] ?? 0.5] as [number, number, number],
  );
  const outline = getStroke(inputs, {
    size: Math.max(el.strokeWidth, 1) * 4.25,
    simulatePressure: el.simulatePressure,
  });
  if (outline.length <= 2) return "";
  const first = outline[0]!;
  let d = `M ${fmt(first[0]!)} ${fmt(first[1]!)} `;
  for (let i = 1; i < outline.length; i++) {
    d += `L ${fmt(outline[i]![0]!)} ${fmt(outline[i]![1]!)} `;
  }
  d += "Z";
  return `<path d="${d}" fill="${escapeXml(el.strokeColor)}" stroke="none"/>`;
}

function textBody(el: TextElement): string {
  const lines = el.text.split("\n");
  const lineHeight = el.fontSize * el.lineHeight;
  let out = "";
  for (let i = 0; i < lines.length; i++) {
    const y = lineHeight * i + el.fontSize * 0.8;
    out += `<text x="0" y="${fmt(y)}" font-size="${fmt(el.fontSize)}" fill="${escapeXml(el.strokeColor)}">${escapeXml(lines[i]!)}</text>`;
  }
  return out;
}

function elementBody(el: ExcalidrawElement): string {
  if (el.type === "text") return textBody(el);
  if (el.type === "image") {
    return `<image width="${fmt(el.width)}" height="${fmt(el.height)}" data-file-id="${escapeXml(el.fileId ?? "")}"/>`;
  }
  if (el.type === "freedraw") return freedrawBody(el);
  return drawableBody(el);
}

function group(el: ExcalidrawElement): string {
  const cx = el.width / 2;
  const cy = el.height / 2;
  let transform = `translate(${fmt(el.x)} ${fmt(el.y)})`;
  if (el.angle !== 0) {
    transform += ` rotate(${fmt((el.angle * 180) / Math.PI)} ${fmt(cx)} ${fmt(cy)})`;
  }
  return `<g transform="${transform}" opacity="${fmt(el.opacity / 100)}">${elementBody(el)}</g>`;
}

/**
 * Export a scene to an SVG string, fitting content with padding. (parity:
 * SVGExporter.swift)
 */
export function exportSvg(scene: Scene, padding = 16): string {
  const box = commonBounds(scene.visibleElements);
  if (box === null) return emptySvg();
  const width = box.width + 2 * padding;
  const height = box.height + 2 * padding;
  const offsetX = padding - box.minX;
  const offsetY = padding - box.minY;
  const background = viewBackgroundColor(scene.appState) ?? "#ffffff";

  let body = `<rect width="${fmt(width)}" height="${fmt(height)}" fill="${escapeXml(background)}"/>\n`;
  for (const el of scene.visibleElements) body += `${group(el)}\n`;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${fmt(width)}" height="${fmt(height)}" viewBox="0 0 ${fmt(width)} ${fmt(height)}">
<g transform="translate(${fmt(offsetX)} ${fmt(offsetY)})">
${body}</g>
</svg>`;
}
