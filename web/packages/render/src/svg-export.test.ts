import { Scene } from "@xs/model";
import { describe, expect, it } from "vitest";
import { exportSvg } from "./svg-export.js";
import { rect, text } from "./test-helpers.js";

describe("SVG export", () => {
  it("empty scene yields a 0-sized SVG", () => {
    const svg = exportSvg(new Scene([]));
    expect(svg).toContain('width="0"');
  });

  it("rectangle SVG has dimensions, a path, and the stroke colour", () => {
    const svg = exportSvg(new Scene([rect({ x: 30, y: 30, w: 100, h: 60 })]), 10);
    expect(svg).toContain('width="120.00"');
    expect(svg).toContain('height="80.00"');
    expect(svg).toContain("<path");
    expect(svg).toContain('stroke="#1e1e1e"');
  });

  it("filled rectangle includes a fill attribute", () => {
    const svg = exportSvg(new Scene([rect({ x: 0, y: 0, w: 100, h: 60, bg: "#ff0000" })]));
    expect(svg).toContain('fill="#ff0000"');
  });

  it("text content is XML-escaped", () => {
    const svg = exportSvg(new Scene([text("a<b>c", { x: 0, y: 0, w: 60, h: 20 })]));
    expect(svg).toContain("a&lt;b&gt;c");
    expect(svg).toContain("<text");
  });

  it("rotated elements get a rotate transform", () => {
    const svg = exportSvg(new Scene([rect({ x: 0, y: 0, w: 100, h: 60, angle: Math.PI / 2 })]));
    expect(svg).toContain("rotate(");
  });
});
