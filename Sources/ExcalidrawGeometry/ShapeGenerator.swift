import ExcalidrawMath
import Foundation

/// Generates the vertex set of a clean shape fitted to a bounding box, used as
/// the "perfect" output when a freehand stroke is snapped (Apple's Snap to
/// Shape). Every shape is returned as an open list of points forming a closed
/// loop (the caller closes it), in scene coordinates.
public enum ShapeGenerator {
    /// A regular `sides`-gon inscribed in `box`, first vertex at the top.
    public static func regularPolygon(sides: Int, in box: BoundingBox) -> [Point] {
        let (cx, cy, rx, ry) = ellipseParams(box)
        return (0 ..< max(sides, 3)).map { i in
            let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(sides)
            return Point(cx + rx * cos(a), cy + ry * sin(a))
        }
    }

    /// An `points`-pointed star inscribed in `box` (`innerRatio` sets the valley
    /// radius), first tip at the top.
    public static func star(points: Int = 5, innerRatio: Double = 0.42, in box: BoundingBox) -> [Point] {
        let (cx, cy, rx, ry) = ellipseParams(box)
        return (0 ..< (max(points, 3) * 2)).map { i in
            let a = -Double.pi / 2 + Double.pi * Double(i) / Double(points)
            let r = i.isMultiple(of: 2) ? 1.0 : innerRatio
            return Point(cx + rx * r * cos(a), cy + ry * r * sin(a))
        }
    }

    /// A heart fitted to `box` (classic parametric heart, sampled `samples` times).
    public static func heart(in box: BoundingBox, samples: Int = 48) -> [Point] {
        var raw: [(Double, Double)] = []
        for i in 0 ..< samples {
            let t = 2 * Double.pi * Double(i) / Double(samples)
            let x = 16 * pow(sin(t), 3)
            // Negate so the point sits at the bottom in y-down coordinates.
            let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
            raw.append((x, y))
        }
        return fit(raw, to: box)
    }

    /// A puffy cloud fitted to `box` — a bumpy closed curve with `lobes` lobes.
    public static func cloud(in box: BoundingBox, lobes: Int = 9, samples: Int = 72) -> [Point] {
        let (cx, cy, rx, ry) = ellipseParams(box)
        return (0 ..< samples).map { i in
            let a = 2 * Double.pi * Double(i) / Double(samples)
            // Rounded bumps: radius dips between lobes, never crossing the centre.
            let r = 0.82 + 0.18 * abs(sin(Double(lobes) * a / 2))
            return Point(cx + rx * r * cos(a), cy + ry * r * sin(a))
        }
    }

    /// A speech bubble fitted to `box`: a rounded-rectangle body over the top
    /// ~72% with a triangular tail descending on the lower-left.
    public static func speechBubble(in box: BoundingBox) -> [Point] {
        let w = box.width, h = box.height
        let bodyBottom = box.minY + h * 0.72
        let r = min(w, h) * 0.18
        let left = box.minX, right = box.maxX, top = box.minY
        var pts: [Point] = []
        /// Clockwise from top-left, rounding each body corner with a few points.
        func arc(_ cxx: Double, _ cyy: Double, _ from: Double, _ to: Double) {
            for k in 0 ... 4 {
                let a = from + (to - from) * Double(k) / 4
                pts.append(Point(cxx + r * cos(a), cyy + r * sin(a)))
            }
        }
        arc(left + r, top + r, Double.pi, 1.5 * Double.pi) // top-left
        arc(right - r, top + r, 1.5 * Double.pi, 2 * Double.pi) // top-right
        arc(right - r, bodyBottom - r, 0, 0.5 * Double.pi) // bottom-right
        // Bottom edge to the tail, then a downward triangular tail, then continue.
        pts.append(Point(left + w * 0.42, bodyBottom))
        pts.append(Point(left + w * 0.28, box.maxY)) // tail tip
        pts.append(Point(left + w * 0.30, bodyBottom))
        arc(left + r, bodyBottom - r, 0.5 * Double.pi, Double.pi) // bottom-left
        return pts
    }

    // MARK: Helpers

    private static func ellipseParams(_ box: BoundingBox) -> (cx: Double, cy: Double, rx: Double, ry: Double) {
        ((box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2, box.width / 2, box.height / 2)
    }

    /// Normalize raw `(x, y)` samples to [0, 1] then map onto `box`.
    private static func fit(_ raw: [(Double, Double)], to box: BoundingBox) -> [Point] {
        let xs = raw.map(\.0), ys = raw.map(\.1)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let spanX = max(maxX - minX, 1e-9), spanY = max(maxY - minY, 1e-9)
        return raw.map { x, y in
            Point(box.minX + (x - minX) / spanX * box.width, box.minY + (y - minY) / spanY * box.height)
        }
    }
}
