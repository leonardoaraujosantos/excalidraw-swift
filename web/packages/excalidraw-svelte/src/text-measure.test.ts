import { describe, expect, it } from "vitest";
import { FontFamily } from "./model/enums.js";
import { fontFamilyCss, fontString, measureTextWidth } from "./text-measure.js";

describe("text-measure", () => {
  it("maps font families to the right CSS stacks (parity with iOS fallbacks)", () => {
    expect(fontFamilyCss(FontFamily.default)).toContain("Excalifont");
    expect(fontFamilyCss(FontFamily.default)).toContain("cursive");
    expect(fontFamilyCss(FontFamily.virgil)).toContain("Bradley Hand");
    expect(fontFamilyCss(FontFamily.cascadia)).toContain("monospace");
    expect(fontFamilyCss(FontFamily.comicShanns)).toContain("monospace");
    expect(fontFamilyCss(FontFamily.helvetica)).toContain("sans-serif");
    // Unknown ids fall back to the hand-drawn stack.
    expect(fontFamilyCss(999)).toContain("Excalifont");
  });

  it("builds a Canvas/CSS font shorthand", () => {
    expect(fontString(20, FontFamily.default)).toBe(`20px ${fontFamilyCss(FontFamily.default)}`);
  });

  it("falls back to the fontSize·0.6 heuristic without a DOM", () => {
    // Under vitest's node environment there is no `document`, so the heuristic
    // is used — this keeps unit tests and golden fixtures deterministic.
    expect(measureTextWidth("hello", 20, FontFamily.default)).toBeCloseTo(5 * 20 * 0.6, 6);
    // Width is the widest line.
    expect(measureTextWidth("hi\nlonger line", 10, FontFamily.default)).toBeCloseTo(
      "longer line".length * 10 * 0.6,
      6,
    );
    expect(measureTextWidth("", 20, FontFamily.default)).toBe(0);
  });
});
