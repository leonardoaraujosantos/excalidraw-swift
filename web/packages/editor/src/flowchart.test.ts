import { Point } from "@cyberdynecorp/excalidraw-math";
import { type ExcalidrawElement, Scene, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { EditorController, type FlowchartDirection } from "./controller.js";

function nodeEditor(): EditorController {
  const node: ExcalidrawElement = {
    ...defaultBase("n", { x: 0, y: 0, width: 100, height: 60, backgroundColor: "#a5d8ff" }),
    type: "rectangle",
  };
  return new EditorController(new Scene([node]));
}

describe("flowchart spawning", () => {
  it("adds a node and arrow to the right", () => {
    const ec = nodeEditor();
    const result = ec.addFlowchartNode("n", "right")!;
    const node = ec.scene.element(result.node)!;
    expect(node.x).toBeCloseTo(200, 9);
    expect(node.y).toBeCloseTo(0, 9);
    expect(node.width).toBe(100);
    expect(node.type).toBe("rectangle");
    expect([...ec.selectedIDs]).toEqual([result.node]);
  });

  it("the arrow is elbow and bound at both ends", () => {
    const ec = nodeEditor();
    const result = ec.addFlowchartNode("n", "down")!;
    const arrow = ec.scene.element(result.arrow)!;
    if (arrow.type === "arrow") {
      expect(arrow.elbowed).toBe(true);
      expect(arrow.startBinding?.elementId).toBe("n");
      expect(arrow.endBinding?.elementId).toBe(result.node);
    }
  });

  it("boundElements registered on both nodes", () => {
    const ec = nodeEditor();
    const result = ec.addFlowchartNode("n", "up")!;
    expect(ec.scene.element("n")?.boundElements?.some((b) => b.id === result.arrow)).toBe(true);
    expect(ec.scene.element(result.node)?.boundElements?.some((b) => b.id === result.arrow)).toBe(
      true,
    );
  });

  it("directions offset correctly", () => {
    const cases: [FlowchartDirection, Point][] = [
      ["left", new Point(-200, 0)],
      ["up", new Point(0, -160)],
    ];
    for (const [direction, expected] of cases) {
      const ec = nodeEditor();
      const result = ec.addFlowchartNode("n", direction)!;
      const node = ec.scene.element(result.node)!;
      expect(node.x).toBeCloseTo(expected.x, 9);
      expect(node.y).toBeCloseTo(expected.y, 9);
    }
  });

  it("rejects a non-bindable source", () => {
    const arrow: ExcalidrawElement = {
      ...defaultBase("a"),
      type: "arrow",
      points: [
        [0, 0],
        [50, 0],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: null,
      elbowed: false,
    };
    const ec = new EditorController(new Scene([arrow]));
    expect(ec.addFlowchartNode("a", "right")).toBeNull();
  });

  it("a second node in the same direction staggers", () => {
    const ec = nodeEditor();
    const first = ec.addFlowchartNode("n", "down")!;
    const second = ec.addFlowchartNode("n", "down")!;
    expect(ec.scene.element(first.node)?.x).not.toBe(ec.scene.element(second.node)?.x);
  });

  it("add node is undoable", () => {
    const ec = nodeEditor();
    ec.addFlowchartNode("n", "right");
    expect(ec.scene.visibleElements.length).toBe(3);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(1);
  });
});
