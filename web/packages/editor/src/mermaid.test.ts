import { Point } from "@cyberdynecorp/excalidraw-math";
import { describe, expect, it } from "vitest";
import { EditorController } from "./controller.js";
import { parseMermaid } from "./mermaid.js";

describe("Mermaid parser", () => {
  it("parses nodes, edges, and shapes", () => {
    const text = `flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C(Go)
    B -->|No| D((Stop))`;
    const elements = parseMermaid(text)!;
    expect(elements).not.toBeNull();
    expect(
      elements.filter((e) => ["rectangle", "diamond", "ellipse"].includes(e.type)).length,
    ).toBe(4);
    expect(elements.filter((e) => e.type === "text").length).toBe(4);
    expect(elements.filter((e) => e.type === "arrow").length).toBe(3);
    expect(elements.find((e) => e.id === "mermaid-A")?.type).toBe("rectangle");
    expect(elements.find((e) => e.id === "mermaid-B")?.type).toBe("diamond");
    expect(elements.find((e) => e.id === "mermaid-D")?.type).toBe("ellipse");
  });

  it("a plain line (---) has no end arrowhead", () => {
    const elements = parseMermaid("graph LR\n A --- B")!;
    const arrow = elements.find((e) => e.type === "arrow")!;
    if (arrow.type === "arrow") expect(arrow.endArrowhead).toBeNull();
  });

  it("arrows bind to nodes", () => {
    const elements = parseMermaid("flowchart TD\n A --> B")!;
    const arrow = elements.find((e) => e.type === "arrow")!;
    if (arrow.type === "arrow") {
      expect(arrow.startBinding?.elementId).toBe("mermaid-A");
      expect(arrow.endBinding?.elementId).toBe("mermaid-B");
      expect(arrow.endArrowhead).toBe("arrow");
    }
  });

  it("text labels are container-bound", () => {
    const elements = parseMermaid("flowchart TD\n A[Hello] --> B[World]")!;
    const label = elements.find((e) => e.id === "mermaid-A-text")!;
    if (label.type === "text") {
      expect(label.text).toBe("Hello");
      expect(label.containerId).toBe("mermaid-A");
    }
  });

  it("TD layering places the target below the source", () => {
    const elements = parseMermaid("flowchart TD\n A --> B")!;
    const a = elements.find((e) => e.id === "mermaid-A")!;
    const b = elements.find((e) => e.id === "mermaid-B")!;
    expect(b.y).toBeGreaterThan(a.y);
  });

  it("non-Mermaid text returns null", () => {
    expect(parseMermaid("just some text\nnot a diagram")).toBeNull();
    expect(parseMermaid("")).toBeNull();
  });

  it("insertMermaid places the diagram at the point and selects it", () => {
    const ec = new EditorController();
    expect(ec.insertMermaid("flowchart TD\n A[X] --> B[Y]", new Point(500, 500))).toBe(true);
    expect(ec.scene.visibleElements.length).toBeGreaterThan(0);
    expect(ec.selectedIDs.size).toBe(ec.scene.visibleElements.length);
    const minX = Math.min(...ec.scene.visibleElements.map((e) => e.x));
    expect(minX).toBeCloseTo(500, 6);
    expect(ec.insertMermaid("not a diagram", new Point(0, 0))).toBe(false);
  });
});
