import { BoundingBox, fixedPointFor } from "@cyberdynecorp/excalidraw-geometry";
import { Point } from "@cyberdynecorp/excalidraw-math";
import {
  type ArrowElement,
  type ExcalidrawElement,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";

/**
 * Parses a subset of Mermaid `flowchart`/`graph` syntax into Excalidraw
 * elements (shapes with bound text + bound arrows), laid out in layers by the
 * declared direction. (parity: MermaidParser.swift)
 */

type Direction = "td" | "tb" | "bt" | "lr" | "rl";
type Shape = "rectangle" | "rounded" | "diamond" | "ellipse";

interface Node {
  id: string;
  label: string;
  shape: Shape;
  order: number;
}
interface Edge {
  from: string;
  to: string;
  label: string | null;
  arrow: boolean;
}
interface NodeSpec {
  id: string;
  label: string | null;
  shape: Shape;
}

const NODE_WIDTH = 140;
const NODE_HEIGHT = 60;
const LAYER_GAP = 80;
const SIBLING_GAP = 40;

const DIRECTIONS: Direction[] = ["td", "tb", "bt", "lr", "rl"];

function unquote(s: string): string {
  let t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) t = t.slice(1, -1);
  return t;
}

function parseDirection(header: string): Direction {
  for (const token of header
    .split(" ")
    .slice(1)
    .map((t) => t.toLowerCase())) {
    if ((DIRECTIONS as string[]).includes(token)) return token as Direction;
  }
  return "td";
}

function parseNodeSpec(raw: string): NodeSpec | null {
  const s = raw.trim();
  const first = s[0];
  if (first === undefined || !/[A-Za-z_]/.test(first)) return null;
  let id = "";
  for (const ch of s) {
    if (/[A-Za-z0-9_]/.test(ch)) id += ch;
    else break;
  }
  if (id.length === 0) return null;
  const body = s.slice(id.length).trim();
  if (body.length === 0) return { id, label: null, shape: "rectangle" };
  const wrappers: [string, string, Shape][] = [
    ["((", "))", "ellipse"],
    ["([", "])", "rounded"],
    ["[", "]", "rectangle"],
    ["{", "}", "diamond"],
    ["(", ")", "rounded"],
  ];
  for (const [open, close, shape] of wrappers) {
    if (
      body.startsWith(open) &&
      body.endsWith(close) &&
      body.length > open.length + close.length - 1
    ) {
      return { id, label: unquote(body.slice(open.length, body.length - close.length)), shape };
    }
  }
  return { id, label: null, shape: "rectangle" };
}

function parseEdge(line: string): {
  left: NodeSpec;
  right: NodeSpec;
  label: string | null;
  arrow: boolean;
} | null {
  for (const op of ["-.->", "==>", "-->", "---"]) {
    const at = line.indexOf(op);
    if (at === -1) continue;
    const leftStr = line.slice(0, at).trim();
    let rightStr = line.slice(at + op.length).trim();
    let label: string | null = null;
    if (rightStr.startsWith("|")) {
      const close = rightStr.indexOf("|", 1);
      if (close !== -1) {
        label = unquote(rightStr.slice(1, close));
        rightStr = rightStr.slice(close + 1).trim();
      }
    }
    const left = parseNodeSpec(leftStr);
    const right = parseNodeSpec(rightStr);
    if (left === null || right === null) return null;
    return { left, right, label, arrow: op !== "---" };
  }
  return null;
}

function position(along: number, across: number, direction: Direction): Point {
  switch (direction) {
    case "td":
    case "tb":
      return new Point(along, across);
    case "bt":
      return new Point(along, -across);
    case "lr":
      return new Point(across, along);
    case "rl":
      return new Point(-across, along);
  }
}

function layout(nodes: Map<string, Node>, edges: Edge[], direction: Direction): Map<string, Point> {
  const inDeg = new Map<string, number>();
  for (const id of nodes.keys()) inDeg.set(id, 0);
  const outgoing = new Map<string, string[]>();
  for (const edge of edges) {
    if (!nodes.has(edge.from) || !nodes.has(edge.to)) continue;
    inDeg.set(edge.to, (inDeg.get(edge.to) ?? 0) + 1);
    const arr = outgoing.get(edge.from) ?? [];
    arr.push(edge.to);
    outgoing.set(edge.from, arr);
  }
  const orderOf = (id: string) => nodes.get(id)!.order;
  const layerOf = new Map<string, number>();
  let queue = [...nodes.keys()]
    .filter((id) => (inDeg.get(id) ?? 0) === 0)
    .sort((a, b) => orderOf(a) - orderOf(b));
  for (const id of queue) layerOf.set(id, 0);
  if (queue.length === 0) {
    const first = [...nodes.keys()].sort((a, b) => orderOf(a) - orderOf(b))[0];
    if (first !== undefined) {
      queue = [first];
      layerOf.set(first, 0);
    }
  }
  let guardCount = 0;
  while (queue.length > 0 && guardCount < nodes.size * nodes.size) {
    const id = queue.shift()!;
    guardCount++;
    for (const next of outgoing.get(id) ?? []) {
      const candidate = (layerOf.get(id) ?? 0) + 1;
      if (candidate > (layerOf.get(next) ?? -1)) {
        layerOf.set(next, candidate);
        queue.push(next);
      }
    }
  }
  for (const id of nodes.keys()) if (!layerOf.has(id)) layerOf.set(id, 0);

  const byLayer = new Map<number, string[]>();
  for (const [id, l] of layerOf) {
    const arr = byLayer.get(l) ?? [];
    arr.push(id);
    byLayer.set(l, arr);
  }
  for (const ids of byLayer.values()) ids.sort((a, b) => orderOf(a) - orderOf(b));

  const positions = new Map<string, Point>();
  for (const [layerIndex, ids] of [...byLayer.entries()].sort((a, b) => a[0] - b[0])) {
    ids.forEach((id, i) => {
      positions.set(
        id,
        position(i * (NODE_WIDTH + SIBLING_GAP), layerIndex * (NODE_HEIGHT + LAYER_GAP), direction),
      );
    });
  }
  return positions;
}

function shapeType(shape: Shape): "rectangle" | "diamond" | "ellipse" {
  if (shape === "diamond") return "diamond";
  if (shape === "ellipse") return "ellipse";
  return "rectangle";
}

function arrowElement(
  edge: Edge,
  index: number,
  from: BoundingBox,
  to: BoundingBox,
  seed: number,
): ArrowElement {
  const start = new Point((from.minX + from.maxX) / 2, from.maxY);
  const end = new Point((to.minX + to.maxX) / 2, to.minY);
  return {
    ...defaultBase(`mermaid-edge-${index}`, {
      x: start.x,
      y: start.y,
      width: Math.abs(end.x - start.x),
      height: Math.abs(end.y - start.y),
      seed,
      strokeColor: "#1e1e1e",
    }),
    type: "arrow",
    points: [
      [0, 0],
      [end.x - start.x, end.y - start.y],
    ],
    startBinding: {
      elementId: `mermaid-${edge.from}`,
      fixedPoint: fixedPointFor(start, from).toArray(),
      mode: "orbit",
    },
    endBinding: {
      elementId: `mermaid-${edge.to}`,
      fixedPoint: fixedPointFor(end, to).toArray(),
      mode: "orbit",
    },
    startArrowhead: null,
    endArrowhead: edge.arrow ? "arrow" : null,
    elbowed: false,
  };
}

function build(
  nodes: Map<string, Node>,
  edges: Edge[],
  positions: Map<string, Point>,
  seed: number,
): ExcalidrawElement[] {
  const elements: ExcalidrawElement[] = [];
  let seedCounter = seed;
  const nextSeed = () => ++seedCounter;
  const bounds = new Map<string, BoundingBox>();

  for (const node of [...nodes.values()].sort((a, b) => a.order - b.order)) {
    const pos = positions.get(node.id);
    if (pos === undefined) continue;
    const elementID = `mermaid-${node.id}`;
    const textID = `mermaid-${node.id}-text`;
    elements.push({
      ...defaultBase(elementID, {
        x: pos.x,
        y: pos.y,
        width: NODE_WIDTH,
        height: NODE_HEIGHT,
        seed: nextSeed(),
        strokeColor: "#1e1e1e",
        backgroundColor: "#ffffff",
        roundness: node.shape === "rounded" ? { type: 3 } : null,
        boundElements: [{ id: textID, type: "text" }],
      }),
      type: shapeType(node.shape),
    });
    bounds.set(node.id, new BoundingBox(pos.x, pos.y, pos.x + NODE_WIDTH, pos.y + NODE_HEIGHT));
    elements.push({
      ...defaultBase(textID, {
        x: pos.x,
        y: pos.y,
        width: NODE_WIDTH,
        height: 25,
        seed: nextSeed(),
      }),
      type: "text",
      ...defaultTextProps({
        fontSize: 16,
        text: node.label,
        textAlign: "center",
        verticalAlign: "middle",
        containerId: elementID,
        originalText: node.label,
      }),
    });
  }

  edges.forEach((edge, index) => {
    const from = bounds.get(edge.from);
    const to = bounds.get(edge.to);
    if (from === undefined || to === undefined) return;
    elements.push(arrowElement(edge, index, from, to, nextSeed()));
  });
  return elements;
}

/** Parse `text` into elements, or `null` when it isn't a recognizable flowchart. */
export function parseMermaid(text: string, seed = 1): ExcalidrawElement[] | null {
  const lines = text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("%%"));
  const header = lines[0];
  if (header === undefined) return null;
  const lower = header.toLowerCase();
  if (!lower.startsWith("flowchart") && !lower.startsWith("graph")) return null;
  const direction = parseDirection(header);

  const nodes = new Map<string, Node>();
  let order = 0;
  const edges: Edge[] = [];
  const ensureNode = (spec: NodeSpec): void => {
    const existing = nodes.get(spec.id);
    if (existing === undefined) {
      nodes.set(spec.id, {
        id: spec.id,
        label: spec.label ?? spec.id,
        shape: spec.shape,
        order: order++,
      });
    } else if (spec.label !== null) {
      existing.label = spec.label;
      existing.shape = spec.shape;
    }
  };

  for (const line of lines.slice(1)) {
    const edge = parseEdge(line);
    if (edge !== null) {
      ensureNode(edge.left);
      ensureNode(edge.right);
      edges.push({ from: edge.left.id, to: edge.right.id, label: edge.label, arrow: edge.arrow });
    } else {
      const node = parseNodeSpec(line);
      if (node !== null) ensureNode(node);
    }
  }
  if (nodes.size === 0) return null;
  return build(nodes, edges, layout(nodes, edges, direction), seed);
}
