import ExcalidrawMath
import Foundation

/// Orthogonal ("elbow") arrow routing via A* over a non-uniform grid
/// (`packages/element/src/elbowArrow.ts`).
///
/// Given two endpoints — each either a bare point or bound to an element's
/// bounding box — this produces a sequence of points forming axis-aligned
/// segments that leave/enter each element perpendicular to its side and avoid
/// crossing the (padded) elements.
public enum ElbowArrow {
    /// Padding grown around bound elements so the route has room to turn.
    public static let basePadding = 40.0
    private static let dedupThreshold = 1.0

    /// Route an elbow arrow from `start` to `end`. Pass the bound element's
    /// bounds in `startBox`/`endBox` when an endpoint is attached to a shape;
    /// pass `nil` for a free endpoint. Returns the simplified corner points
    /// (always including the exact `start` and `end`).
    public static func route(
        start: Point, startBox: BoundingBox?,
        end: Point, endBox: BoundingBox?
    ) -> [Point] {
        let startHeading = startBox.map { Heading.from(box: $0, toward: start) }
            ?? Heading.from(point: end, origin: start)
        let endHeading = endBox.map { Heading.from(box: $0, toward: end) }
            ?? Heading.from(point: start, origin: end)

        let startEl = startBox ?? pointBounds(start)
        let endEl = endBox ?? pointBounds(end)
        let common = commonAABB([startEl, endEl])
        let aabbs = generateDynamicAABBs(
            startEl, endEl, common,
            startDifference: offsetFromHeading(startHeading, basePadding, basePadding),
            endDifference: offsetFromHeading(endHeading, basePadding, basePadding)
        )

        let startDongle = donglePosition(aabbs[0], startHeading, start)
        let endDongle = donglePosition(aabbs[1], endHeading, end)

        let grid = calculateGrid(
            aabbs: aabbs,
            start: startDongle, startHeading: startHeading,
            end: endDongle, endHeading: endHeading,
            common: common
        )

        guard let startNode = node(at: startDongle, in: grid),
              let endNode = node(at: endDongle, in: grid) else {
            return [start, end]
        }

        let dongleOverlap = pointInside(startDongle, aabbs[1]) || pointInside(endDongle, aabbs[0])
        guard let path = astar(
            start: startNode, end: endNode, grid: grid,
            startHeading: startHeading, endHeading: endHeading,
            aabbs: dongleOverlap ? [] : aabbs
        ) else {
            return [start, end]
        }

        var points = path.map(\.pos)
        points.insert(start, at: 0)
        points.append(end)
        return simplify(points)
    }

    // MARK: Fixed-segment editing

    /// Descriptor for a draggable interior segment of an elbow polyline.
    public struct Segment: Equatable, Sendable {
        /// Segment between `points[index - 1]` and `points[index]`.
        public let index: Int
        public let start: Point
        public let end: Point
        public let isHorizontal: Bool
        public var midpoint: Point {
            start.midpoint(to: end)
        }
    }

    /// The interior ("fixable") segments — every segment except the first and
    /// last, which touch the endpoints and so can't be pinned (matching
    /// upstream's invariant).
    public static func fixableSegments(_ points: [Point]) -> [Segment] {
        guard points.count >= 4 else { return [] }
        return (2 ... (points.count - 2)).map { i in
            let a = points[i - 1], b = points[i]
            return Segment(index: i, start: a, end: b, isHorizontal: abs(a.y - b.y) < abs(a.x - b.x))
        }
    }

    /// Move the segment at `index` so it passes through `drag` (perpendicular to
    /// the segment), shifting the two shared endpoints. Neighboring segments
    /// stay orthogonal because only the moved segment's coordinate changes.
    public static func moveSegment(_ points: [Point], index: Int, to drag: Point) -> [Point] {
        guard points.indices.contains(index), index >= 1 else { return points }
        var pts = points
        let a = pts[index - 1], b = pts[index]
        if abs(a.y - b.y) < abs(a.x - b.x) {
            // Horizontal segment → drag changes its y.
            pts[index - 1] = Point(a.x, drag.y)
            pts[index] = Point(b.x, drag.y)
        } else {
            // Vertical segment → drag changes its x.
            pts[index - 1] = Point(drag.x, a.y)
            pts[index] = Point(drag.x, b.y)
        }
        return pts
    }

    /// Re-anchor only the first and last segments so the path follows moved
    /// endpoints while every interior (pinned) segment stays put. Used to keep a
    /// manually-shaped elbow arrow attached when its bound shapes move.
    public static func followEndpoints(_ points: [Point], newStart: Point, newEnd: Point) -> [Point] {
        guard points.count >= 4 else { return points }
        var pts = points
        let g0 = pts[0], g1 = pts[1]
        pts[0] = newStart
        pts[1] = abs(g0.y - g1.y) < abs(g0.x - g1.x) ? Point(g1.x, newStart.y) : Point(newStart.x, g1.y)

        let n = pts.count
        let h0 = pts[n - 1], h1 = pts[n - 2]
        pts[n - 1] = newEnd
        pts[n - 2] = abs(h0.y - h1.y) < abs(h0.x - h1.x) ? Point(h1.x, newEnd.y) : Point(newEnd.x, h1.y)
        return pts
    }

    // MARK: Grid + A* node

    private final class Node {
        var f = 0.0, g = 0.0, h = 0.0
        var closed = false
        var visited = false
        var parent: Node?
        let col: Int
        let row: Int
        let pos: Point
        init(col: Int, row: Int, pos: Point) {
            self.col = col
            self.row = row
            self.pos = pos
        }
    }

    private struct Grid {
        let rows: Int
        let cols: Int
        let data: [Node]
        func node(col: Int, row: Int) -> Node? {
            guard col >= 0, col < cols, row >= 0, row < rows else { return nil }
            return data[row * cols + col]
        }
    }

    private static func calculateGrid(
        aabbs: [BoundingBox], start: Point, startHeading: Heading,
        end: Point, endHeading: Heading, common: BoundingBox
    ) -> Grid {
        var horizontal = Set<Double>()
        var vertical = Set<Double>()

        if startHeading.isHorizontal { vertical.insert(start.y) } else { horizontal.insert(start.x) }
        if endHeading.isHorizontal { vertical.insert(end.y) } else { horizontal.insert(end.x) }

        for aabb in aabbs {
            horizontal.insert(aabb.minX)
            horizontal.insert(aabb.maxX)
            vertical.insert(aabb.minY)
            vertical.insert(aabb.maxY)
        }
        horizontal.insert(common.minX)
        horizontal.insert(common.maxX)
        vertical.insert(common.minY)
        vertical.insert(common.maxY)

        let xs = horizontal.sorted()
        let ys = vertical.sorted()
        var data: [Node] = []
        data.reserveCapacity(xs.count * ys.count)
        for (row, y) in ys.enumerated() {
            for (col, x) in xs.enumerated() {
                data.append(Node(col: col, row: row, pos: Point(x, y)))
            }
        }
        return Grid(rows: ys.count, cols: xs.count, data: data)
    }

    private static func node(at point: Point, in grid: Grid) -> Node? {
        grid.data.first { $0.pos.x == point.x && $0.pos.y == point.y }
    }

    private static func neighbors(of n: Node, in grid: Grid) -> [Node?] {
        [
            grid.node(col: n.col, row: n.row - 1), // up
            grid.node(col: n.col + 1, row: n.row), // right
            grid.node(col: n.col, row: n.row + 1), // down
            grid.node(col: n.col - 1, row: n.row) // left
        ]
    }

    private static func headingForNeighbor(_ index: Int) -> Heading {
        switch index {
        case 0: .up
        case 1: .right
        case 2: .down
        default: .left
        }
    }

    private static func astar(
        start: Node, end: Node, grid: Grid,
        startHeading: Heading, endHeading: Heading, aabbs: [BoundingBox]
    ) -> [Node]? {
        let bendMultiplier = manhattan(start.pos, end.pos)
        var open: [Node] = [start]

        while !open.isEmpty {
            // Pop the lowest-f node.
            var bestIndex = 0
            for i in open.indices where open[i].f < open[bestIndex].f {
                bestIndex = i
            }
            let current = open.remove(at: bestIndex)
            if current.closed { continue }
            if current === end { return path(to: current, from: start) }
            current.closed = true

            let ns = neighbors(of: current, in: grid)
            for i in 0 ..< 4 {
                guard let neighbor = ns[i], !neighbor.closed else { continue }

                // Block if the segment midpoint falls inside an obstacle.
                let half = Point((current.pos.x + neighbor.pos.x) / 2, (current.pos.y + neighbor.pos.y) / 2)
                if aabbs.contains(where: { pointInside(half, $0) }) { continue }

                let neighborHeading = headingForNeighbor(i)
                let previousDirection = current.parent.map {
                    Heading.from(vector: Vector(current.pos.x - $0.pos.x, current.pos.y - $0.pos.y))
                } ?? startHeading

                // Never double back, and never re-enter the start/end against its heading.
                let isReverse = previousDirection.flipped() == neighborHeading
                    || (start === neighbor && neighborHeading == startHeading)
                    || (end === neighbor && neighborHeading == endHeading)
                if isReverse { continue }

                let directionChange = previousDirection != neighborHeading
                let gScore = current.g + manhattan(neighbor.pos, current.pos)
                    + (directionChange ? pow(bendMultiplier, 3) : 0)

                if !neighbor.visited || gScore < neighbor.g {
                    let estBends = estimateSegmentCount(neighbor, end, neighborHeading, endHeading)
                    neighbor.visited = true
                    neighbor.parent = current
                    neighbor.h = manhattan(end.pos, neighbor.pos) + Double(estBends) * pow(bendMultiplier, 2)
                    neighbor.g = gScore
                    neighbor.f = neighbor.g + neighbor.h
                    open.append(neighbor) // a stale copy will be skipped via `closed`
                }
            }
        }
        return nil
    }

    private static func path(to node: Node, from start: Node) -> [Node] {
        var result: [Node] = []
        var current: Node? = node
        while let c = current, c.parent != nil {
            result.insert(c, at: 0)
            current = c.parent
        }
        result.insert(start, at: 0)
        return result
    }

    // MARK: Heuristic — estimated remaining bend count

    // swiftlint:disable:next cyclomatic_complexity
    private static func estimateSegmentCount(
        _ start: Node,
        _ end: Node,
        _ startHeading: Heading,
        _ endHeading: Heading
    ) -> Int {
        let s = start.pos, e = end.pos
        switch endHeading {
        case .right:
            switch startHeading {
            case .right:
                if s.x >= e.x { return 4 }
                return s.y == e.y ? 0 : 2
            case .up: return (s.y > e.y && s.x < e.x) ? 1 : 3
            case .down: return (s.y < e.y && s.x < e.x) ? 1 : 3
            case .left: return s.y == e.y ? 4 : 2
            }
        case .left:
            switch startHeading {
            case .right: return s.y == e.y ? 4 : 2
            case .up: return (s.y > e.y && s.x > e.x) ? 1 : 3
            case .down: return (s.y < e.y && s.x > e.x) ? 1 : 3
            case .left:
                if s.x <= e.x { return 4 }
                return s.y == e.y ? 0 : 2
            }
        case .up:
            switch startHeading {
            case .right: return (s.y > e.y && s.x < e.x) ? 1 : 3
            case .up:
                if s.y >= e.y { return 4 }
                return s.x == e.x ? 0 : 2
            case .down: return s.x == e.x ? 4 : 2
            case .left: return (s.y > e.y && s.x > e.x) ? 1 : 3
            }
        case .down:
            switch startHeading {
            case .right: return (s.y < e.y && s.x < e.x) ? 1 : 3
            case .up: return s.x == e.x ? 4 : 2
            case .down:
                if s.y <= e.y { return 4 }
                return s.x == e.x ? 0 : 2
            case .left: return (s.y < e.y && s.x > e.x) ? 1 : 3
            }
        }
    }

    // MARK: Dynamic AABBs

    /// Resizable, always-touching bounding boxes with a minimum extent set by
    /// the two element boxes (`generateDynamicAABBs`, without the corner hack).
    private static func generateDynamicAABBs(
        _ a: BoundingBox, _ b: BoundingBox, _ common: BoundingBox,
        startDifference: (up: Double, right: Double, down: Double, left: Double),
        endDifference: (up: Double, right: Double, down: Double, left: Double)
    ) -> [BoundingBox] {
        let (sU, sR, sD, sL) = startDifference
        let (eU, eR, eD, eL) = endDifference

        let first = BoundingBox(
            minX: a.minX > b.maxX
                ? (a.minY > b.maxY || a.maxY < b.minY ? min((a.minX + b.maxX) / 2, a.minX - sL) : (a.minX + b.maxX) / 2)
                : (a.minX > b.minX ? a.minX - sL : common.minX - sL),
            minY: a.minY > b.maxY
                ? (a.minX > b.maxX || a.maxX < b.minX ? min((a.minY + b.maxY) / 2, a.minY - sU) : (a.minY + b.maxY) / 2)
                : (a.minY > b.minY ? a.minY - sU : common.minY - sU),
            maxX: a.maxX < b.minX
                ? (a.minY > b.maxY || a.maxY < b.minY ? max((a.maxX + b.minX) / 2, a.maxX + sR) : (a.maxX + b.minX) / 2)
                : (a.maxX < b.maxX ? a.maxX + sR : common.maxX + sR),
            maxY: a.maxY < b.minY
                ? (a.minX > b.maxX || a.maxX < b.minX ? max((a.maxY + b.minY) / 2, a.maxY + sD) : (a.maxY + b.minY) / 2)
                : (a.maxY < b.maxY ? a.maxY + sD : common.maxY + sD)
        )
        let second = BoundingBox(
            minX: b.minX > a.maxX
                ? (b.minY > a.maxY || b.maxY < a.minY ? min((b.maxX + a.maxX) / 2, b.minX - eL) : (b.minX + a.maxX) / 2)
                : (b.minX > a.minX ? b.minX - eL : common.minX - eL),
            minY: b.minY > a.maxY
                ? (b.minX > a.maxX || b.maxX < a.minX ? min((b.minY + a.maxY) / 2, b.minY - eU) : (b.minY + a.maxY) / 2)
                : (b.minY > a.minY ? b.minY - eU : common.minY - eU),
            maxX: b.maxX < a.minX
                ? (b.minY > a.maxY || b.maxY < a.minY ? max((b.maxX + a.minX) / 2, b.maxX + eR) : (b.maxX + a.minX) / 2)
                : (b.maxX < a.maxX ? b.maxX + eR : common.maxX + eR),
            maxY: b.maxY < a.minY
                ? (b.minX > a.maxX || b.maxX < a.minX ? max((b.maxY + a.minY) / 2, b.maxY + eD) : (b.maxY + a.minY) / 2)
                : (b.maxY < a.maxY ? b.maxY + eD : common.maxY + eD)
        )
        return [first, second]
    }

    // MARK: Small helpers

    private static func pointBounds(_ p: Point) -> BoundingBox {
        BoundingBox(minX: p.x - 2, minY: p.y - 2, maxX: p.x + 2, maxY: p.y + 2)
    }

    private static func commonAABB(_ boxes: [BoundingBox]) -> BoundingBox {
        BoundingBox(
            minX: boxes.map(\.minX).min() ?? 0,
            minY: boxes.map(\.minY).min() ?? 0,
            maxX: boxes.map(\.maxX).max() ?? 0,
            maxY: boxes.map(\.maxY).max() ?? 0
        )
    }

    private static func pointInside(_ p: Point, _ box: BoundingBox) -> Bool {
        p.x > box.minX && p.x < box.maxX && p.y > box.minY && p.y < box.maxY
    }

    private static func manhattan(_ a: Point, _ b: Point) -> Double {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    /// Project the endpoint onto the matching side of its dynamic AABB
    /// (`getDonglePosition`).
    private static func donglePosition(_ box: BoundingBox, _ heading: Heading, _ p: Point) -> Point {
        switch heading {
        case .up: Point(p.x, box.minY)
        case .right: Point(box.maxX, p.y)
        case .down: Point(p.x, box.maxY)
        case .left: Point(box.minX, p.y)
        }
    }

    /// Per-side padding tuple, `head` on the heading's side, `side` elsewhere
    /// (`offsetFromHeading`).
    private static func offsetFromHeading(
        _ heading: Heading, _ head: Double, _ side: Double
    ) -> (up: Double, right: Double, down: Double, left: Double) {
        switch heading {
        case .up: (head, side, side, side)
        case .right: (side, head, side, side)
        case .down: (side, side, head, side)
        case .left: (side, side, side, head)
        }
    }

    // MARK: Simplification

    /// Drop redundant collinear points, then near-duplicate short segments
    /// (`getElbowArrowCornerPoints` + `removeElbowArrowShortSegments`).
    private static func simplify(_ points: [Point]) -> [Point] {
        cornerPoints(removeShortSegments(cornerPoints(points)))
    }

    private static func cornerPoints(_ points: [Point]) -> [Point] {
        guard points.count > 1 else { return points }
        var previousHorizontal = abs(points[0].y - points[1].y) < abs(points[0].x - points[1].x)
        return points.enumerated().filter { index, p in
            if index == 0 || index == points.count - 1 { return true }
            let next = points[index + 1]
            let nextHorizontal = abs(p.y - next.y) < abs(p.x - next.x)
            defer { previousHorizontal = nextHorizontal }
            return previousHorizontal != nextHorizontal
        }.map(\.element)
    }

    private static func removeShortSegments(_ points: [Point]) -> [Point] {
        guard points.count >= 4 else { return points }
        return points.enumerated().filter { index, p in
            if index == 0 || index == points.count - 1 { return true }
            return points[index - 1].distance(to: p) > dedupThreshold
        }.map(\.element)
    }
}
