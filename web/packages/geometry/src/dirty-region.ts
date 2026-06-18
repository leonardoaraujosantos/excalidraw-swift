import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";
import { semanticEqual } from "@cyberdynecorp/excalidraw-model";
import type { BoundingBox } from "./bounding-box.js";
import { bounds } from "./element-geometry.js";

/**
 * The bounding box enclosing every element added, removed, or changed between
 * `oldList` and `newList` — the basis for incremental redraw. `null` when
 * nothing changed. (parity: DirtyRegion.swift)
 */
export function dirtyRegion(
  oldList: ExcalidrawElement[],
  newList: ExcalidrawElement[],
): BoundingBox | null {
  const oldById = new Map(oldList.map((el) => [el.id, el] as const));
  const newById = new Map(newList.map((el) => [el.id, el] as const));

  let region: BoundingBox | null = null;
  const accumulate = (box: BoundingBox): void => {
    region = region === null ? box : region.union(box);
  };

  for (const el of newList) {
    const previous = oldById.get(el.id);
    if (previous !== undefined) {
      if (!semanticEqual(previous, el)) {
        accumulate(bounds(previous));
        accumulate(bounds(el));
      }
    } else {
      accumulate(bounds(el)); // added
    }
  }
  for (const el of oldList) {
    if (!newById.has(el.id)) accumulate(bounds(el)); // removed
  }
  return region;
}
