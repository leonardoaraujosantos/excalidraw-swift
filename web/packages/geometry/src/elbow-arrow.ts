import { Point, Vector } from "@cyberdynecorp/excalidraw-math";
import { BoundingBox } from "./bounding-box.js";
import {
  type Heading,
  flippedHeading,
  headingFromBoxToward,
  headingFromPoint,
  headingFromVector,
  isHorizontal,
} from "./heading.js";

const BASE_PADDING = 40;
const DEDUP_THRESHOLD = 1;

interface SidePadding {
  up: number;
  right: number;
  down: number;
  left: number;
}

/** Descriptor for a draggable interior segment of an elbow polyline. */
export interface ElbowSegment {
  index: number;
  start: Point;
  end: Point;
  isHorizontal: boolean;
  midpoint: Point;
}

class Node {
  f = 0;
  g = 0;
  h = 0;
  closed = false;
  visited = false;
  parent: Node | null = null;
  constructor(
    public col: number,
    public row: number,
    public pos: Point,
  ) {}
}

class Grid {
  constructor(
    public rows: number,
    public cols: number,
    public data: Node[],
  ) {}

  node(col: number, row: number): Node | null {
    if (col < 0 || col >= this.cols || row < 0 || row >= this.rows) return null;
    return this.data[row * this.cols + col]!;
  }
}

function pointBounds(p: Point): BoundingBox {
  return new BoundingBox(p.x - 2, p.y - 2, p.x + 2, p.y + 2);
}

function commonAABB(boxes: BoundingBox[]): BoundingBox {
  return new BoundingBox(
    Math.min(...boxes.map((b) => b.minX)),
    Math.min(...boxes.map((b) => b.minY)),
    Math.max(...boxes.map((b) => b.maxX)),
    Math.max(...boxes.map((b) => b.maxY)),
  );
}

function pointInside(p: Point, box: BoundingBox): boolean {
  return p.x > box.minX && p.x < box.maxX && p.y > box.minY && p.y < box.maxY;
}

function manhattan(a: Point, b: Point): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

function donglePosition(box: BoundingBox, heading: Heading, p: Point): Point {
  switch (heading) {
    case "up":
      return new Point(p.x, box.minY);
    case "right":
      return new Point(box.maxX, p.y);
    case "down":
      return new Point(p.x, box.maxY);
    case "left":
      return new Point(box.minX, p.y);
  }
}

function offsetFromHeading(heading: Heading, head: number, side: number): SidePadding {
  switch (heading) {
    case "up":
      return { up: head, right: side, down: side, left: side };
    case "right":
      return { up: side, right: head, down: side, left: side };
    case "down":
      return { up: side, right: side, down: head, left: side };
    case "left":
      return { up: side, right: side, down: side, left: head };
  }
}

function generateDynamicAABBs(
  a: BoundingBox,
  b: BoundingBox,
  common: BoundingBox,
  s: SidePadding,
  e: SidePadding,
): [BoundingBox, BoundingBox] {
  const first = new BoundingBox(
    a.minX > b.maxX
      ? a.minY > b.maxY || a.maxY < b.minY
        ? Math.min((a.minX + b.maxX) / 2, a.minX - s.left)
        : (a.minX + b.maxX) / 2
      : a.minX > b.minX
        ? a.minX - s.left
        : common.minX - s.left,
    a.minY > b.maxY
      ? a.minX > b.maxX || a.maxX < b.minX
        ? Math.min((a.minY + b.maxY) / 2, a.minY - s.up)
        : (a.minY + b.maxY) / 2
      : a.minY > b.minY
        ? a.minY - s.up
        : common.minY - s.up,
    a.maxX < b.minX
      ? a.minY > b.maxY || a.maxY < b.minY
        ? Math.max((a.maxX + b.minX) / 2, a.maxX + s.right)
        : (a.maxX + b.minX) / 2
      : a.maxX < b.maxX
        ? a.maxX + s.right
        : common.maxX + s.right,
    a.maxY < b.minY
      ? a.minX > b.maxX || a.maxX < b.minX
        ? Math.max((a.maxY + b.minY) / 2, a.maxY + s.down)
        : (a.maxY + b.minY) / 2
      : a.maxY < b.maxY
        ? a.maxY + s.down
        : common.maxY + s.down,
  );
  const second = new BoundingBox(
    b.minX > a.maxX
      ? b.minY > a.maxY || b.maxY < a.minY
        ? Math.min((b.maxX + a.maxX) / 2, b.minX - e.left)
        : (b.minX + a.maxX) / 2
      : b.minX > a.minX
        ? b.minX - e.left
        : common.minX - e.left,
    b.minY > a.maxY
      ? b.minX > a.maxX || b.maxX < a.minX
        ? Math.min((b.minY + a.maxY) / 2, b.minY - e.up)
        : (b.minY + a.maxY) / 2
      : b.minY > a.minY
        ? b.minY - e.up
        : common.minY - e.up,
    b.maxX < a.minX
      ? b.minY > a.maxY || b.maxY < a.minY
        ? Math.max((b.maxX + a.minX) / 2, b.maxX + e.right)
        : (b.maxX + a.minX) / 2
      : b.maxX < a.maxX
        ? b.maxX + e.right
        : common.maxX + e.right,
    b.maxY < a.minY
      ? b.minX > a.maxX || b.maxX < a.minX
        ? Math.max((b.maxY + a.minY) / 2, b.maxY + e.down)
        : (b.maxY + a.minY) / 2
      : b.maxY < a.maxY
        ? b.maxY + e.down
        : common.maxY + e.down,
  );
  return [first, second];
}

function calculateGrid(
  aabbs: BoundingBox[],
  start: Point,
  startHeading: Heading,
  end: Point,
  endHeading: Heading,
  common: BoundingBox,
): Grid {
  const horizontal = new Set<number>();
  const vertical = new Set<number>();

  if (isHorizontal(startHeading)) vertical.add(start.y);
  else horizontal.add(start.x);
  if (isHorizontal(endHeading)) vertical.add(end.y);
  else horizontal.add(end.x);

  for (const aabb of aabbs) {
    horizontal.add(aabb.minX);
    horizontal.add(aabb.maxX);
    vertical.add(aabb.minY);
    vertical.add(aabb.maxY);
  }
  horizontal.add(common.minX);
  horizontal.add(common.maxX);
  vertical.add(common.minY);
  vertical.add(common.maxY);

  const xs = [...horizontal].sort((p, q) => p - q);
  const ys = [...vertical].sort((p, q) => p - q);
  const data: Node[] = [];
  ys.forEach((y, row) => {
    xs.forEach((x, col) => {
      data.push(new Node(col, row, new Point(x, y)));
    });
  });
  return new Grid(ys.length, xs.length, data);
}

function nodeAt(point: Point, grid: Grid): Node | null {
  return grid.data.find((n) => n.pos.x === point.x && n.pos.y === point.y) ?? null;
}

function neighbors(n: Node, grid: Grid): (Node | null)[] {
  return [
    grid.node(n.col, n.row - 1),
    grid.node(n.col + 1, n.row),
    grid.node(n.col, n.row + 1),
    grid.node(n.col - 1, n.row),
  ];
}

function headingForNeighbor(index: number): Heading {
  switch (index) {
    case 0:
      return "up";
    case 1:
      return "right";
    case 2:
      return "down";
    default:
      return "left";
  }
}

// swiftlint parity: estimated remaining bend count
function estimateSegmentCount(
  start: Node,
  end: Node,
  startHeading: Heading,
  endHeading: Heading,
): number {
  const s = start.pos;
  const e = end.pos;
  switch (endHeading) {
    case "right":
      switch (startHeading) {
        case "right":
          return s.x >= e.x ? 4 : s.y === e.y ? 0 : 2;
        case "up":
          return s.y > e.y && s.x < e.x ? 1 : 3;
        case "down":
          return s.y < e.y && s.x < e.x ? 1 : 3;
        case "left":
          return s.y === e.y ? 4 : 2;
      }
      break;
    case "left":
      switch (startHeading) {
        case "right":
          return s.y === e.y ? 4 : 2;
        case "up":
          return s.y > e.y && s.x > e.x ? 1 : 3;
        case "down":
          return s.y < e.y && s.x > e.x ? 1 : 3;
        case "left":
          return s.x <= e.x ? 4 : s.y === e.y ? 0 : 2;
      }
      break;
    case "up":
      switch (startHeading) {
        case "right":
          return s.y > e.y && s.x < e.x ? 1 : 3;
        case "up":
          return s.y >= e.y ? 4 : s.x === e.x ? 0 : 2;
        case "down":
          return s.x === e.x ? 4 : 2;
        case "left":
          return s.y > e.y && s.x > e.x ? 1 : 3;
      }
      break;
    case "down":
      switch (startHeading) {
        case "right":
          return s.y < e.y && s.x < e.x ? 1 : 3;
        case "up":
          return s.x === e.x ? 4 : 2;
        case "down":
          return s.y <= e.y ? 4 : s.x === e.x ? 0 : 2;
        case "left":
          return s.y < e.y && s.x > e.x ? 1 : 3;
      }
      break;
  }
  return 3;
}

function reconstructPath(node: Node, start: Node): Node[] {
  const result: Node[] = [];
  let current: Node | null = node;
  while (current !== null && current.parent !== null) {
    result.unshift(current);
    current = current.parent;
  }
  result.unshift(start);
  return result;
}

function astar(
  start: Node,
  end: Node,
  grid: Grid,
  startHeading: Heading,
  endHeading: Heading,
  aabbs: BoundingBox[],
): Node[] | null {
  const bendMultiplier = manhattan(start.pos, end.pos);
  const open: Node[] = [start];

  while (open.length > 0) {
    let bestIndex = 0;
    for (let i = 0; i < open.length; i++) {
      if (open[i]!.f < open[bestIndex]!.f) bestIndex = i;
    }
    const current = open.splice(bestIndex, 1)[0]!;
    if (current.closed) continue;
    if (current === end) return reconstructPath(current, start);
    current.closed = true;

    const ns = neighbors(current, grid);
    for (let i = 0; i < 4; i++) {
      const neighbor = ns[i];
      if (neighbor === null || neighbor === undefined || neighbor.closed) continue;

      const half = new Point(
        (current.pos.x + neighbor.pos.x) / 2,
        (current.pos.y + neighbor.pos.y) / 2,
      );
      if (aabbs.some((box) => pointInside(half, box))) continue;

      const neighborHeading = headingForNeighbor(i);
      const previousDirection =
        current.parent !== null
          ? headingFromVector(
              new Vector(
                current.pos.x - current.parent.pos.x,
                current.pos.y - current.parent.pos.y,
              ),
            )
          : startHeading;

      const isReverse =
        flippedHeading(previousDirection) === neighborHeading ||
        (start === neighbor && neighborHeading === startHeading) ||
        (end === neighbor && neighborHeading === endHeading);
      if (isReverse) continue;

      const directionChange = previousDirection !== neighborHeading;
      const gScore =
        current.g +
        manhattan(neighbor.pos, current.pos) +
        (directionChange ? bendMultiplier ** 3 : 0);

      if (!neighbor.visited || gScore < neighbor.g) {
        const estBends = estimateSegmentCount(neighbor, end, neighborHeading, endHeading);
        neighbor.visited = true;
        neighbor.parent = current;
        neighbor.h = manhattan(end.pos, neighbor.pos) + estBends * bendMultiplier ** 2;
        neighbor.g = gScore;
        neighbor.f = neighbor.g + neighbor.h;
        open.push(neighbor);
      }
    }
  }
  return null;
}

function cornerPoints(points: Point[]): Point[] {
  if (points.length <= 1) return points;
  let previousHorizontal =
    Math.abs(points[0]!.y - points[1]!.y) < Math.abs(points[0]!.x - points[1]!.x);
  const result: Point[] = [];
  for (let index = 0; index < points.length; index++) {
    const p = points[index]!;
    if (index === 0 || index === points.length - 1) {
      result.push(p);
      continue;
    }
    const next = points[index + 1]!;
    const nextHorizontal = Math.abs(p.y - next.y) < Math.abs(p.x - next.x);
    if (previousHorizontal !== nextHorizontal) result.push(p);
    previousHorizontal = nextHorizontal;
  }
  return result;
}

function removeShortSegments(points: Point[]): Point[] {
  if (points.length < 4) return points;
  return points.filter((p, index) => {
    if (index === 0 || index === points.length - 1) return true;
    return points[index - 1]!.distance(p) > DEDUP_THRESHOLD;
  });
}

function simplify(points: Point[]): Point[] {
  return cornerPoints(removeShortSegments(cornerPoints(points)));
}

function makeSegment(points: Point[], index: number): ElbowSegment {
  const a = points[index - 1]!;
  const b = points[index]!;
  return {
    index,
    start: a,
    end: b,
    isHorizontal: Math.abs(a.y - b.y) < Math.abs(a.x - b.x),
    midpoint: a.midpoint(b),
  };
}

/**
 * Orthogonal ("elbow") arrow routing via A* over a non-uniform grid. (parity:
 * ElbowArrow.swift)
 */
export const ElbowArrow = {
  BASE_PADDING,

  /** Route an elbow arrow from `start` to `end`, optionally bound to boxes. */
  route(
    start: Point,
    startBox: BoundingBox | null,
    end: Point,
    endBox: BoundingBox | null,
  ): Point[] {
    const startHeading =
      startBox !== null ? headingFromBoxToward(startBox, start) : headingFromPoint(end, start);
    const endHeading =
      endBox !== null ? headingFromBoxToward(endBox, end) : headingFromPoint(start, end);

    const startEl = startBox ?? pointBounds(start);
    const endEl = endBox ?? pointBounds(end);
    const common = commonAABB([startEl, endEl]);
    const aabbs = generateDynamicAABBs(
      startEl,
      endEl,
      common,
      offsetFromHeading(startHeading, BASE_PADDING, BASE_PADDING),
      offsetFromHeading(endHeading, BASE_PADDING, BASE_PADDING),
    );

    const startDongle = donglePosition(aabbs[0], startHeading, start);
    const endDongle = donglePosition(aabbs[1], endHeading, end);

    const grid = calculateGrid(aabbs, startDongle, startHeading, endDongle, endHeading, common);
    const startNode = nodeAt(startDongle, grid);
    const endNode = nodeAt(endDongle, grid);
    if (startNode === null || endNode === null) return [start, end];

    const dongleOverlap = pointInside(startDongle, aabbs[1]) || pointInside(endDongle, aabbs[0]);
    const path = astar(
      startNode,
      endNode,
      grid,
      startHeading,
      endHeading,
      dongleOverlap ? [] : aabbs,
    );
    if (path === null) return [start, end];

    const points = path.map((n) => n.pos);
    points.unshift(start);
    points.push(end);
    return simplify(points);
  },

  /** Interior ("fixable") segments — every segment except the first and last. */
  fixableSegments(points: Point[]): ElbowSegment[] {
    if (points.length < 4) return [];
    const out: ElbowSegment[] = [];
    for (let index = 2; index <= points.length - 2; index++) out.push(makeSegment(points, index));
    return out;
  },

  /** Every draggable segment, including the first and last. */
  segments(points: Point[]): ElbowSegment[] {
    if (points.length < 2) return [];
    const out: ElbowSegment[] = [];
    for (let index = 1; index <= points.length - 1; index++) out.push(makeSegment(points, index));
    return out;
  },

  /** Move the segment at `index` to pass through `drag`; returns new points + index. */
  moveSegment(points: Point[], index: number, drag: Point): { points: Point[]; index: number } {
    if (index < 1 || index >= points.length) return { points, index };
    const n = points.length;
    const a = points[index - 1]!;
    const b = points[index]!;
    const horizontal = Math.abs(a.y - b.y) < Math.abs(a.x - b.x);
    const pts = [...points];

    if (index >= 2 && index <= n - 2) {
      if (horizontal) {
        pts[index - 1] = new Point(a.x, drag.y);
        pts[index] = new Point(b.x, drag.y);
      } else {
        pts[index - 1] = new Point(drag.x, a.y);
        pts[index] = new Point(drag.x, b.y);
      }
      return { points: pts, index };
    }

    if (index === 1) {
      if (horizontal) {
        pts[1] = new Point(b.x, drag.y);
        pts.splice(1, 0, new Point(a.x, drag.y));
      } else {
        pts[1] = new Point(drag.x, b.y);
        pts.splice(1, 0, new Point(drag.x, a.y));
      }
      return { points: pts, index: 2 };
    }

    if (horizontal) {
      pts[n - 2] = new Point(a.x, drag.y);
      pts.splice(n - 1, 0, new Point(b.x, drag.y));
    } else {
      pts[n - 2] = new Point(drag.x, a.y);
      pts.splice(n - 1, 0, new Point(drag.x, b.y));
    }
    return { points: pts, index: n - 1 };
  },

  /** Re-anchor only the first/last segments so the path follows moved endpoints. */
  followEndpoints(points: Point[], newStart: Point, newEnd: Point): Point[] {
    if (points.length < 4) return points;
    const pts = [...points];
    const g0 = pts[0]!;
    const g1 = pts[1]!;
    pts[0] = newStart;
    pts[1] =
      Math.abs(g0.y - g1.y) < Math.abs(g0.x - g1.x)
        ? new Point(g1.x, newStart.y)
        : new Point(newStart.x, g1.y);

    const n = pts.length;
    const h0 = pts[n - 1]!;
    const h1 = pts[n - 2]!;
    pts[n - 1] = newEnd;
    pts[n - 2] =
      Math.abs(h0.y - h1.y) < Math.abs(h0.x - h1.x)
        ? new Point(h1.x, newEnd.y)
        : new Point(newEnd.x, h1.y);
    return pts;
  },
} as const;
