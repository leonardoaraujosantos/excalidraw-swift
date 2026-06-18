import {
  type Arrowhead,
  type BaseProperties,
  type FillStyle,
  FontFamily,
  type StrokeStyle,
  defaultBase,
} from "@cyberdynecorp/excalidraw-model";

/**
 * Style properties applied to newly created elements, mirroring the
 * `currentItem*` fields of upstream AppState. (parity: CurrentItemProperties.swift)
 */
export interface CurrentItem {
  strokeColor: string;
  backgroundColor: string;
  fillStyle: FillStyle;
  strokeWidth: number;
  strokeStyle: StrokeStyle;
  roughness: number;
  opacity: number;
  fontFamily: number;
  fontSize: number;
  elbowed: boolean;
  roundEdges: boolean;
  startArrowhead: Arrowhead | null;
  endArrowhead: Arrowhead | null;
}

export function defaultCurrentItem(): CurrentItem {
  return {
    strokeColor: "#1e1e1e",
    backgroundColor: "transparent",
    fillStyle: "hachure",
    strokeWidth: 2,
    strokeStyle: "solid",
    roughness: 1,
    opacity: 100,
    fontFamily: FontFamily.default,
    fontSize: 20,
    elbowed: false,
    roundEdges: true,
    startArrowhead: null,
    endArrowhead: "arrow",
  };
}

/** Build base properties for a new element carrying the current styles. */
export function makeBase(
  item: CurrentItem,
  id: string,
  seed: number,
  x: number,
  y: number,
): BaseProperties {
  return defaultBase(id, {
    x,
    y,
    strokeColor: item.strokeColor,
    backgroundColor: item.backgroundColor,
    fillStyle: item.fillStyle,
    strokeWidth: item.strokeWidth,
    strokeStyle: item.strokeStyle,
    roughness: item.roughness,
    opacity: item.opacity,
    seed,
  });
}
