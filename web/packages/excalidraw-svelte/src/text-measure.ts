// Text font resolution and measurement, shared by the editor (which sizes text
// elements) and the Core-Graphics-equivalent Canvas2D renderer (which draws
// them). Keeping both on the *same* font string is what makes a text element's
// stored width/height — and therefore its selection box — match the glyphs that
// are actually painted. (parity: FontRegistry + TextLayout.measure in Swift)

import { FontFamily } from "./model/enums.js";

/**
 * CSS `font-family` stack for an Excalidraw font-family id. Mirrors the iOS
 * `FontRegistry` fallbacks: the hand-drawn families (Virgil/Excalifont/Nunito/
 * Lilita One) resolve to a hand-drawn system face (Bradley Hand on Apple,
 * Comic Sans / Segoe Print elsewhere, then generic `cursive`), the code
 * families to a monospace face, and the rest to a sans-serif face.
 */
export function fontFamilyCss(fontFamily: number): string {
  switch (fontFamily) {
    case FontFamily.cascadia:
    case FontFamily.comicShanns:
      return '"Cascadia Code", "Comic Shanns", ui-monospace, "Menlo", monospace';
    case FontFamily.helvetica:
    case FontFamily.liberationSans:
    case FontFamily.assistant:
      return '"Helvetica Neue", "Liberation Sans", Arial, sans-serif';
    default:
      // virgil, excalifont, nunito, lilitaOne, and unknown ids → hand-drawn.
      return '"Excalifont", "Virgil", "Bradley Hand", "Comic Sans MS", "Segoe Print", cursive';
  }
}

/** A CSS/Canvas `font` shorthand (`<size>px <family-stack>`). */
export function fontString(fontSize: number, fontFamily: number): string {
  return `${fontSize}px ${fontFamilyCss(fontFamily)}`;
}

// One reusable measuring context, created lazily. `null` in non-DOM
// environments (unit tests, SSR) where we fall back to the heuristic below.
let measureContext: CanvasRenderingContext2D | null | undefined;
function context(): CanvasRenderingContext2D | null {
  if (measureContext !== undefined) return measureContext;
  measureContext =
    typeof document !== "undefined" ? document.createElement("canvas").getContext("2d") : null;
  return measureContext;
}

/**
 * Width of the widest line of `text`, measured with the font it will actually
 * be rendered in. In a browser this uses Canvas `measureText` (true glyph
 * advance for the resolved face); without a DOM it falls back to the
 * `fontSize · 0.6` monospace approximation so unit tests and the cross-language
 * golden fixtures stay deterministic.
 */
export function measureTextWidth(text: string, fontSize: number, fontFamily: number): number {
  const lines = text.split("\n");
  const ctx = context();
  if (ctx === null) {
    const longest = lines.reduce((m, l) => Math.max(m, l.length), 0);
    return longest * fontSize * 0.6;
  }
  ctx.font = fontString(fontSize, fontFamily);
  return lines.reduce((m, l) => Math.max(m, ctx.measureText(l).width), 0);
}
