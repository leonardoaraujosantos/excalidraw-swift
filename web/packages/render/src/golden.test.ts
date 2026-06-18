import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  type ExcalidrawElement,
  Scene,
  SceneDocument,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { exportSvg } from "./svg-export.js";

const GOLDEN_DIR = join(dirname(fileURLToPath(import.meta.url)), "golden");
const UPDATE = process.env.UPDATE_GOLDEN === "1";

function fixture(name: string): string {
  return readFileSync(join(process.cwd(), "..", "Fixtures", name), "utf8");
}

/**
 * Assert `content` equals the committed golden, or (re)write it when
 * `UPDATE_GOLDEN=1`. The canonical-JSON goldens are language-neutral — the Swift
 * twin's `JSONEncoder(.sortedKeys)` produces the same bytes — so they double as
 * the cross-language serialization contract; the SVG goldens lock the TS render
 * pipeline (rough.js + perfect-freehand + serialization) against regressions.
 */
function assertGolden(name: string, content: string): void {
  const path = join(GOLDEN_DIR, name);
  if (UPDATE) {
    mkdirSync(GOLDEN_DIR, { recursive: true });
    writeFileSync(path, content);
    return;
  }
  expect(existsSync(path), `missing golden ${name} (run with UPDATE_GOLDEN=1)`).toBe(true);
  expect(content).toBe(readFileSync(path, "utf8"));
}

/** A deterministic scene covering every renderable element kind (fixed seeds). */
function richScene(): Scene {
  const els: ExcalidrawElement[] = [
    {
      ...defaultBase("rect", {
        x: 20,
        y: 20,
        width: 120,
        height: 80,
        seed: 11,
        backgroundColor: "#a5d8ff",
        fillStyle: "solid",
        roundness: { type: 3 },
      }),
      type: "rectangle",
    },
    {
      ...defaultBase("ell", {
        x: 180,
        y: 20,
        width: 100,
        height: 80,
        seed: 12,
        backgroundColor: "#b2f2bb",
      }),
      type: "ellipse",
    },
    {
      ...defaultBase("dia", { x: 320, y: 20, width: 90, height: 90, seed: 13 }),
      type: "diamond",
    },
    {
      ...defaultBase("line", { x: 20, y: 140, width: 120, height: 60, seed: 14 }),
      type: "line",
      points: [
        [0, 0],
        [120, 0],
        [120, 60],
        [0, 0],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: null,
      polygon: true,
    },
    {
      ...defaultBase("arr", { x: 180, y: 160, width: 120, height: 0, seed: 15 }),
      type: "arrow",
      points: [
        [0, 0],
        [120, 0],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: "arrow",
      elbowed: false,
    },
    {
      ...defaultBase("free", { x: 320, y: 140, width: 60, height: 60, seed: 16 }),
      type: "freedraw",
      points: [
        [0, 0],
        [30, 20],
        [10, 50],
        [60, 60],
      ],
      pressures: [0.2, 0.5, 0.8, 1],
      simulatePressure: false,
    },
    {
      ...defaultBase("txt", { x: 20, y: 240, width: 140, height: 25, seed: 17 }),
      type: "text",
      ...defaultTextProps({ text: "Golden <scene>", originalText: "Golden <scene>" }),
    },
    {
      ...defaultBase("frm", { x: 200, y: 230, width: 220, height: 120, seed: 18 }),
      type: "frame",
      name: "Frame 1",
    },
  ];
  return new Scene(els, { viewBackgroundColor: "#ffffff" });
}

describe("golden snapshots", () => {
  const cases: { name: string; scene: () => Scene }[] = [
    {
      name: "minimal_scene",
      scene: () => SceneDocument.decode(fixture("minimal_scene.excalidraw")),
    },
    { name: "rich_scene", scene: richScene },
  ];

  for (const c of cases) {
    it(`${c.name}: canonical JSON is stable (cross-language contract)`, () => {
      assertGolden(`${c.name}.json`, SceneDocument.encode(c.scene()));
    });
    it(`${c.name}: SVG render is stable`, () => {
      assertGolden(`${c.name}.svg`, exportSvg(c.scene()));
    });
  }

  it("rendering is deterministic (seeded rough.js)", () => {
    expect(exportSvg(richScene())).toBe(exportSvg(richScene()));
    expect(SceneDocument.encode(richScene())).toBe(SceneDocument.encode(richScene()));
  });
});
