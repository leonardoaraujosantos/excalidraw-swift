import { Point } from "@xs/math";
import { type ExcalidrawElement, Scene, decodeFile, defaultBase } from "@xs/model";
import { describe, expect, it } from "vitest";
import { EditorController } from "./controller.js";
import { drag, makeEditor } from "./test-helpers.js";

function rect(id: string, w = 30, h = 20): ExcalidrawElement {
  return { ...defaultBase(id, { width: w, height: h }), type: "rectangle" };
}

describe("element links", () => {
  function editor(): EditorController {
    const ec = makeEditor([{ ...defaultBase("r", { width: 50, height: 50 }), type: "rectangle" }]);
    ec.selectAll();
    return ec;
  }

  it("set and clear a link", () => {
    const ec = editor();
    ec.setLink("https://example.com");
    expect(ec.scene.element("r")?.link).toBe("https://example.com");
    expect(ec.selectionLink).toBe("https://example.com");
    ec.setLink("   ");
    expect(ec.scene.element("r")?.link).toBeNull();
  });

  it("link is undoable", () => {
    const ec = editor();
    ec.setLink("https://a.com");
    expect(ec.undo()).toBe(true);
    expect(ec.scene.element("r")?.link).toBeNull();
  });

  it("selectionLink is null for a multi-select", () => {
    const ec = editor();
    ec.store.modifyScene((s) =>
      s.add({ ...defaultBase("r2", { x: 100, width: 50, height: 50 }), type: "rectangle" }),
    );
    ec.selectAll();
    ec.setLink("https://x.com");
    expect(ec.selectionLink).toBeNull();
  });
});

describe("copy / paste", () => {
  it("copy is null for an empty selection", () => {
    expect(makeEditor([rect("a")]).copyData()).toBeNull();
  });

  it("copy/paste round-trip offsets and reselects", () => {
    const ec = makeEditor([rect("a")]);
    ec.selectAll();
    const data = ec.copyData();
    expect(data).not.toBeNull();
    ec.paste(data!);
    expect(ec.scene.visibleElements.length).toBe(2);
    expect(ec.selectedIDs.has("a")).toBe(false);
    expect(ec.selectedElements[0]?.x).toBe(10);
  });

  it("paste ignores garbage", () => {
    const ec = makeEditor([rect("a")]);
    ec.paste("not json");
    expect(ec.scene.visibleElements.length).toBe(1);
  });

  it("copy includes image files", () => {
    const img: ExcalidrawElement = {
      ...defaultBase("i", { width: 10, height: 10 }),
      type: "image",
      fileId: "f1",
      status: "saved",
      scale: [1, 1],
      crop: null,
    };
    const scene = new Scene(
      [img],
      {},
      {
        f1: { mimeType: "image/png", id: "f1", dataURL: "data:image/png;base64,AA==", created: 0 },
      },
    );
    const ec = new EditorController(scene);
    ec.selectAll();
    const data = ec.copyData()!;
    expect(decodeFile(data).files.f1?.mimeType).toBe("image/png");
  });
});

describe("sticky notes", () => {
  it("creates a filled container with bound text", () => {
    const ec = new EditorController();
    const note = ec.createStickyNote(new Point(20, 20));
    const container = ec.scene.element(note.container)!;
    const text = ec.scene.element(note.text)!;
    expect(container.type).toBe("rectangle");
    expect(container.fillStyle).toBe("solid");
    expect(container.backgroundColor).toBe(EditorController.stickyNoteColor);
    expect(container.roundness).not.toBeNull();
    expect(container.boundElements?.some((b) => b.id === note.text)).toBe(true);
    if (text.type === "text") expect(text.containerId).toBe(note.container);
    expect(text.groupIds).toEqual(container.groupIds);
    expect([...ec.selectedIDs]).toEqual([note.container]);
  });

  it("custom colour", () => {
    const ec = new EditorController();
    const note = ec.createStickyNote(new Point(0, 0), "#a5d8ff");
    expect(ec.scene.element(note.container)?.backgroundColor).toBe("#a5d8ff");
  });

  it("boundTextHit finds the note", () => {
    const ec = new EditorController();
    const note = ec.createStickyNote(new Point(0, 0));
    const found = ec.boundTextHit(new Point(80, 80));
    expect(found?.container).toBe(note.container);
    expect(found?.text).toBe(note.text);
  });

  it("clearing bound text keeps the element", () => {
    const ec = new EditorController();
    const note = ec.createStickyNote(new Point(0, 0));
    ec.setText(note.text, "hello");
    ec.setText(note.text, "");
    const text = ec.scene.element(note.text);
    expect(text).toBeDefined();
    if (text?.type === "text") expect(text.text).toBe("");
  });

  it("moving a sticky note carries its bound text, keeping bounds tight (regression)", () => {
    const ec = new EditorController();
    const note = ec.createStickyNote(new Point(100, 100));
    const text0 = ec.scene.element(note.text)!;
    // createStickyNote selects only the container; dragging it must still move
    // the bound text, or the label strands and the group's bounds balloon.
    drag(ec, new Point(180, 180), new Point(80, 80)); // centre → delta (-100, -100)

    const container = ec.scene.element(note.container)!;
    const text = ec.scene.element(note.text)!;
    expect([container.x, container.y]).toEqual([0, 0]);
    expect([text.x, text.y]).toEqual([text0.x - 100, text0.y - 100]);

    // Selecting the whole group yields a tight box (the container's bounds).
    ec.selectAll();
    const b = ec.selectionBounds!;
    expect([b.minX, b.minY, b.maxX, b.maxY]).toEqual([0, 0, 160, 160]);
  });
});

describe("tables", () => {
  const cells = (ec: EditorController) =>
    ec.scene.visibleElements.filter((e) => e.type === "rectangle");

  it("builds a grid of bound cells", () => {
    const ec = new EditorController();
    const group = ec.createTable(new Point(0, 0), 2, 3);
    expect(ec.scene.visibleElements.length).toBe(12);
    expect(cells(ec).length).toBe(6);
    for (const cell of cells(ec)) {
      expect(cell.groupIds).toEqual([group]);
      expect(cell.boundElements?.length).toBe(1);
      expect(ec.tableGroupID(cell.id)).toBe(group);
    }
  });

  it("selecting one cell selects the whole table", () => {
    const ec = new EditorController();
    ec.createTable(new Point(0, 0), 2, 2);
    const one = cells(ec)[0]!;
    expect(ec.groupSiblings(one.id).size).toBe(8);
  });

  it("add row adds one cell per column", () => {
    const ec = new EditorController();
    const group = ec.createTable(new Point(0, 0), 2, 3);
    const before = cells(ec).length;
    ec.addTableRow(group);
    expect(cells(ec).length).toBe(before + 3);
  });

  it("add column adds one cell per row", () => {
    const ec = new EditorController();
    const group = ec.createTable(new Point(0, 0), 2, 3);
    ec.addTableColumn(group);
    expect(cells(ec).length).toBe(2 * 3 + 2);
  });

  it("cell text is editable via boundTextHit", () => {
    const ec = new EditorController();
    ec.createTable(new Point(0, 0), 1, 1);
    const found = ec.boundTextHit(new Point(60, 22));
    expect(found).not.toBeNull();
    ec.setText(found!.text, "x");
    expect(ec.scene.element(found!.text)).toBeDefined();
  });

  it("create table is one undo step", () => {
    const ec = new EditorController();
    ec.createTable(new Point(0, 0), 2, 2);
    expect(ec.undo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(0);
  });
});

describe("charts", () => {
  const bars = (ec: EditorController) =>
    ec.scene.visibleElements.filter((e) => e.type === "rectangle");

  it("bar chart has one grouped bar per value", () => {
    const ec = new EditorController();
    const group = ec.createChart(new Point(0, 0), [10, 20, 40], [], "bar")!;
    expect(bars(ec).length).toBe(3);
    for (const bar of bars(ec)) expect(bar.groupIds).toEqual([group]);
    const heights = bars(ec)
      .slice()
      .sort((a, b) => a.x - b.x)
      .map((b) => b.height);
    expect(heights[0]).toBeCloseTo(heights[2]! / 4, 6);
    expect(heights[2]).toBeGreaterThan(heights[1]!);
  });

  it("bar heights are proportional", () => {
    const ec = new EditorController();
    ec.createChart(new Point(0, 0), [50, 100], [], "bar");
    const heights = bars(ec)
      .slice()
      .sort((a, b) => a.x - b.x)
      .map((b) => b.height);
    expect(heights[0]).toBeCloseTo(heights[1]! / 2, 6);
  });

  it("line chart produces a single polyline", () => {
    const ec = new EditorController();
    ec.createChart(new Point(0, 0), [1, 3, 2, 5], [], "line");
    const lines = ec.scene.visibleElements.filter((e) => e.type === "line");
    expect(lines.some((l) => l.type === "line" && l.points.length === 4)).toBe(true);
  });

  it("labels become text", () => {
    const ec = new EditorController();
    ec.createChart(new Point(0, 0), [1, 2], ["A", "B"], "bar");
    const texts = ec.scene.visibleElements.flatMap((e) => (e.type === "text" ? [e.text] : []));
    expect(new Set(texts)).toEqual(new Set(["A", "B"]));
  });

  it("empty values produce nothing", () => {
    const ec = new EditorController();
    expect(ec.createChart(new Point(0, 0), [], [], "bar")).toBeNull();
    expect(ec.scene.visibleElements.length).toBe(0);
  });

  it("chart is one undo step", () => {
    const ec = new EditorController();
    ec.createChart(new Point(0, 0), [1, 2, 3], [], "bar");
    expect(ec.undo()).toBe(true);
    expect(ec.scene.visibleElements.length).toBe(0);
  });
});
