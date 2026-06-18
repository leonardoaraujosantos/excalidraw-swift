import {
  type ExcalidrawElement,
  type FillStyle,
  type StrokeStyle,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";

interface Opts {
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  angle?: number;
  bg?: string;
  fillStyle?: FillStyle;
  strokeStyle?: StrokeStyle;
  rounded?: boolean;
}

function base(o: Opts) {
  return defaultBase("e", {
    x: o.x ?? 0,
    y: o.y ?? 0,
    width: o.w ?? 0,
    height: o.h ?? 0,
    angle: o.angle ?? 0,
    backgroundColor: o.bg ?? "transparent",
    fillStyle: o.fillStyle ?? "solid",
    strokeStyle: o.strokeStyle ?? "solid",
    roundness: o.rounded ? { type: 3 } : null,
  });
}

export function rect(o: Opts = {}): ExcalidrawElement {
  return { ...base(o), type: "rectangle" };
}
export function ellipse(o: Opts = {}): ExcalidrawElement {
  return { ...base(o), type: "ellipse" };
}
export function diamond(o: Opts = {}): ExcalidrawElement {
  return { ...base(o), type: "diamond" };
}
export function text(content: string, o: Opts = {}): ExcalidrawElement {
  return {
    ...base(o),
    type: "text",
    ...defaultTextProps({ text: content, originalText: content }),
  };
}
export function arrow(points: [number, number][], o: Opts = {}): ExcalidrawElement {
  return {
    ...base(o),
    type: "arrow",
    points,
    startBinding: null,
    endBinding: null,
    startArrowhead: null,
    endArrowhead: null,
    elbowed: false,
  };
}
