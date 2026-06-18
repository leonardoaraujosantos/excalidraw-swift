import rough from "roughjs";
import type { Drawable, Op } from "roughjs/bin/core";
import { describe, expect, it } from "vitest";

/**
 * Cross-language op-set parity, the TS mirror of Swift's `RoughJSParityTests`.
 *
 * The Swift `RoughKit` is a re-port of rough.js whose geometry is pinned to
 * reference values captured from the real rough.js 4.6.6 (`rough.generator()`,
 * fixed seed, default options). The TS twin renders with that *same* npm
 * package, so asserting against the *same* constants proves all three agree:
 * rough.js ⇔ Swift `RoughKit` ⇔ TS `@cyberdynecorp/excalidraw-render`. If any drifts, CI fails here.
 */
const gen = rough.generator();

type FlatOp = [string, number[]];

function flatten(drawable: Drawable): FlatOp[] {
  const out: FlatOp[] = [];
  for (const set of drawable.sets) {
    for (const op of set.ops as Op[]) {
      out.push([op.op, [...op.data]]);
    }
  }
  return out;
}

function assertMatches(drawable: Drawable, expected: FlatOp[]): void {
  const actual = flatten(drawable);
  expect(actual.length, "op count differs").toBe(expected.length);
  for (let i = 0; i < expected.length; i++) {
    const [expName, expData] = expected[i]!;
    const [actName, actData] = actual[i]!;
    expect(actName, `op ${i} name`).toBe(expName);
    expect(actData.length, `op ${i} arity`).toBe(expData.length);
    for (let j = 0; j < expData.length; j++) {
      expect(actData[j]!, `op ${i} coord ${j}`).toBeCloseTo(expData[j]!, 4);
    }
  }
}

describe("rough.js op-set parity (vs Swift RoughKit reference)", () => {
  it("line matches the rough.js reference", () => {
    const expected: FlatOp[] = [
      ["move", [0.857263, 0.963885]],
      ["bcurveTo", [19.680696, 0.960515, 39.440775, -1.932821, 99.206405, 0.392336]],
      ["move", [-0.648666, 0.264599]],
      ["bcurveTo", [22.574642, 0.381984, 44.356771, -0.187689, 99.419626, 0.752816]],
    ];
    assertMatches(gen.line(0, 0, 100, 0, { seed: 1 }), expected);
  });

  it("rectangle matches the rough.js reference", () => {
    const expected: FlatOp[] = [
      ["move", [0.857263, 0.963885]],
      ["bcurveTo", [19.680696, 0.960515, 39.440775, -1.932821, 99.206405, 0.392336]],
      ["move", [-0.648666, 0.264599]],
      ["bcurveTo", [22.574642, 0.381984, 44.356771, -0.187689, 99.419626, 0.752816]],
      ["move", [101.536704, -1.749433]],
      ["bcurveTo", [100.868044, 12.105373, 101.55958, 20.10944, 101.390548, 49.130645]],
      ["move", [100.297678, -0.799274]],
      ["bcurveTo", [100.399429, 12.55967, 99.422961, 26.866888, 100.406877, 50.352244]],
      ["move", [101.052802, 49.78656]],
      ["bcurveTo", [79.463181, 50.796231, 55.181911, 50.252706, 1.836457, 49.596477]],
      ["move", [99.056573, 49.856268]],
      ["bcurveTo", [62.320868, 50.378278, 25.613406, 50.106814, 0.93895, 50.041844]],
      ["move", [-0.720604, 49.718532]],
      ["bcurveTo", [0.897899, 34.131153, -0.834534, 21.499064, 0.5918, -1.206081]],
      ["move", [0.217957, 50.998223]],
      ["bcurveTo", [-1.083369, 31.157748, -0.577315, 12.722883, 0.440741, 0.98803]],
    ];
    assertMatches(gen.rectangle(0, 0, 100, 50, { seed: 1 }), expected);
  });

  it("ellipse matches the rough.js reference", () => {
    const expected: FlatOp[] = [
      ["move", [61.055643, 1.210651]],
      ["bcurveTo", [69.072286, 1.929735, 78.273558, 6.547635, 84.077909, 10.414811]],
      ["bcurveTo", [89.88226, 14.281988, 94.148629, 19.463209, 95.881751, 24.413709]],
      ["bcurveTo", [97.614872, 29.364209, 97.506554, 35.201406, 94.476639, 40.117809]],
      ["bcurveTo", [91.446724, 45.034212, 84.626228, 50.796286, 77.702262, 53.912127]],
      ["bcurveTo", [70.778295, 57.027969, 61.48791, 58.751641, 52.932838, 58.812859]],
      ["bcurveTo", [44.377766, 58.874077, 33.782546, 57.035684, 26.371829, 54.279434]],
      ["bcurveTo", [18.961112, 51.523184, 12.486028, 46.753648, 8.468536, 42.27536]],
      ["bcurveTo", [4.451044, 37.797071, 1.425272, 32.575102, 2.266877, 27.409704]],
      ["bcurveTo", [3.108481, 22.244305, 8.038119, 15.282302, 13.518165, 11.28297]],
      ["bcurveTo", [18.99821, 7.283637, 25.803128, 4.836997, 35.14715, 3.41371]],
      ["bcurveTo", [44.491172, 1.990422, 62.819276, 2.34457, 69.582297, 2.743243]],
      ["bcurveTo", [76.345317, 3.141916, 76.238602, 5.175945, 75.725273, 5.805749]],
      ["move", [36.532249, 1.200682]],
      ["bcurveTo", [43.860093, -0.411811, 53.552906, 0.658185, 61.830903, 2.372162]],
      ["bcurveTo", [70.1089, 4.08614, 80.558248, 7.543382, 86.200234, 11.484545]],
      ["bcurveTo", [91.84222, 15.425708, 94.235548, 20.853802, 95.682819, 26.019138]],
      ["bcurveTo", [97.13009, 31.184475, 98.178839, 37.678292, 94.883861, 42.476565]],
      ["bcurveTo", [91.588882, 47.274838, 83.339706, 52.30637, 75.912948, 54.808777]],
      ["bcurveTo", [68.486189, 57.311184, 58.94845, 57.339187, 50.32331, 57.491006]],
      ["bcurveTo", [41.69817, 57.642825, 31.434946, 58.077999, 24.162108, 55.719692]],
      ["bcurveTo", [16.889269, 53.361385, 10.286062, 48.23443, 6.686281, 43.341163]],
      ["bcurveTo", [3.086501, 38.447896, 1.614157, 31.722135, 2.563425, 26.360088]],
      ["bcurveTo", [3.512692, 20.998042, 6.802891, 15.081133, 12.381885, 11.168883]],
      ["bcurveTo", [17.96088, 7.256633, 31.827755, 4.243138, 36.037391, 2.886586]],
      ["bcurveTo", [40.247027, 1.530035, 37.152482, 2.62658, 37.639701, 3.029573]],
    ];
    assertMatches(gen.ellipse(50, 30, 100, 60, { seed: 1 }), expected);
  });

  it("filled-rectangle outline matches the rough.js reference (fresh seed, independent of fill)", () => {
    const expectedOutline: FlatOp[] = [
      ["move", [0.857263, 0.963885]],
      ["bcurveTo", [7.680426, 1.082109, 15.440236, -1.811228, 39.206405, 0.392336]],
      ["move", [-0.648666, 0.264599]],
      ["bcurveTo", [9.293528, 0.641013, 17.794544, 0.071341, 39.419626, 0.752816]],
      ["move", [41.536704, -1.749433]],
      ["bcurveTo", [40.914216, 9.93035, 41.605752, 15.759394, 41.390548, 39.130645]],
      ["move", [40.297678, -0.799274]],
      ["bcurveTo", [40.36795, 9.875713, 39.391481, 21.498973, 40.406877, 40.352244]],
      ["move", [41.052802, 39.78656]],
      ["bcurveTo", [32.403529, 40.202675, 21.062608, 39.65915, 1.836457, 39.596477]],
      ["move", [39.056573, 39.856268]],
      ["bcurveTo", [24.875623, 40.309602, 10.722916, 40.038138, 0.93895, 40.041844]],
      ["move", [-0.720604, 39.718532]],
      ["bcurveTo", [0.970473, 26.999246, -0.76196, 17.235251, 0.5918, -1.206081]],
      ["move", [0.217957, 40.998223]],
      ["bcurveTo", [-1.021847, 24.795411, -0.515793, 9.998208, 0.440741, 0.98803]],
    ];
    const drawable = gen.rectangle(0, 0, 40, 40, { seed: 1, fill: "#f00", fillStyle: "hachure" });
    const outline = drawable.sets.find((s) => s.type === "path");
    expect(outline).toBeDefined();
    assertMatches({ ...drawable, sets: [outline!] } as Drawable, expectedOutline);
  });

  it("hachure fill is the same order of magnitude as rough.js", () => {
    const drawable = gen.rectangle(0, 0, 40, 40, { seed: 1, fill: "#f00", fillStyle: "hachure" });
    const fill = drawable.sets.find((s) => s.type === "fillSketch");
    expect(fill).toBeDefined();
    // rough.js emits ~60 ops for this shape; Swift's scan-line is approximate.
    expect(fill!.ops.length).toBeGreaterThan(40);
    expect(fill!.ops.length).toBeLessThan(80);
  });
});
