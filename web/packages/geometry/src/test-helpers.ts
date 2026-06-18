import {
  type ArrowElement,
  type BoundElement,
  type ExcalidrawElement,
  type FreedrawElement,
  type ImageElement,
  type LinearElement,
  type LocalPoint,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";

interface ElOpts {
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  angle?: number;
  bg?: string;
  boundElements?: BoundElement[];
}

function baseFrom(o: ElOpts) {
  return defaultBase("e", {
    x: o.x ?? 0,
    y: o.y ?? 0,
    width: o.w ?? 0,
    height: o.h ?? 0,
    angle: o.angle ?? 0,
    backgroundColor: o.bg ?? "transparent",
    boundElements: o.boundElements ?? null,
  });
}

export function rectEl(o: ElOpts = {}): ExcalidrawElement {
  return { ...baseFrom(o), type: "rectangle" };
}
export function shapeEl(
  type: "diamond" | "ellipse" | "embeddable" | "iframe",
  o: ElOpts = {},
): ExcalidrawElement {
  return { ...baseFrom(o), type };
}
export function textEl(o: ElOpts = {}): ExcalidrawElement {
  return { ...baseFrom(o), type: "text", ...defaultTextProps() } satisfies ExcalidrawElement;
}
export function imageEl(o: ElOpts = {}): ExcalidrawElement {
  return {
    ...baseFrom(o),
    type: "image",
    fileId: null,
    status: "pending",
    scale: [1, 1],
    crop: null,
  } satisfies ImageElement;
}
export function arrowEl(points: LocalPoint[], o: ElOpts = {}): ExcalidrawElement {
  return {
    ...baseFrom(o),
    type: "arrow",
    points,
    startBinding: null,
    endBinding: null,
    startArrowhead: null,
    endArrowhead: null,
    elbowed: false,
  } satisfies ArrowElement;
}
export function lineEl(points: LocalPoint[], polygon: boolean, o: ElOpts = {}): ExcalidrawElement {
  return {
    ...baseFrom(o),
    type: "line",
    points,
    startBinding: null,
    endBinding: null,
    startArrowhead: null,
    endArrowhead: null,
    polygon,
  } satisfies LinearElement;
}
export function freedrawEl(points: LocalPoint[], o: ElOpts = {}): ExcalidrawElement {
  return {
    ...baseFrom(o),
    type: "freedraw",
    points,
    pressures: [],
    simulatePressure: true,
  } satisfies FreedrawElement;
}
