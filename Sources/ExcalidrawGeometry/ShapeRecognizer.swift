import ExcalidrawMath
import Foundation

/// A shape a freehand stroke can be snapped to.
public enum RecognizedShape: Equatable, Sendable {
    case line, rectangle, diamond, ellipse, triangle
    case pentagon, hexagon, star, heart, cloud, speechBubble

    /// Shapes built as a closed polygon-line from `ShapeRecognition.vertices`
    /// (everything except the native box/ellipse kinds and the open line).
    public var isPolyline: Bool {
        switch self {
        case .line, .rectangle, .diamond, .ellipse: false
        default: true
        }
    }
}

/// The result of recognizing a freehand stroke: the shape, its bounding box,
/// and (for line/polyline shapes) the concrete vertices to build it from.
public struct ShapeRecognition: Equatable, Sendable {
    public let shape: RecognizedShape
    public let bounds: BoundingBox
    public let vertices: [Point]
}

/// Recognizes a freehand stroke as a clean geometric shape and snaps it to a
/// perfect figure (Apple's "Snap to Shape"). Basic shapes are classified by
/// Ramer–Douglas–Peucker corner count + circularity; richer shapes (star,
/// heart, cloud, speech bubble) by radial/feature signatures. Polygonal output
/// is regenerated cleanly via `ShapeGenerator`.
public enum ShapeRecognizer {
    /// Recognize `points` (a freehand stroke), or `nil` if it doesn't match a
    /// known shape. `bounds`/`vertices` come back in the input coordinate space.
    public static func recognize(_ points: [Point]) -> ShapeRecognition? {
        guard points.count >= 2, let box = BoundingBox(points: points) else { return nil }
        let diagonal = (box.width * box.width + box.height * box.height).squareRoot()
        guard diagonal > 1 else { return nil }

        let closed = points.count >= 3 && (points.first!.distance(to: points.last!) < diagonal * 0.25)
        let epsilon = diagonal * 0.08
        // RDP on a closed loop can keep a collinear mid-edge point; a cleanup
        // pass drops vertices that lie on the segment between their neighbours.
        let simplified = removeCollinear(rdp(points, epsilon: epsilon), epsilon: epsilon)

        if !closed {
            return simplified.count <= 2
                ? ShapeRecognition(shape: .line, bounds: box, vertices: [points.first!, points.last!])
                : nil
        }

        // Distinctive complex shapes first (they can mimic a low corner count).
        // Heart is checked before the speech bubble, whose "wide top, narrow
        // bottom" signature a heart would otherwise match.
        if detectStar(simplified, box) {
            return polyline(.star, ShapeGenerator.star(in: box), box)
        }
        if detectHeart(points, box) {
            return polyline(.heart, ShapeGenerator.heart(in: box), box)
        }
        if detectCloud(points, box) {
            return polyline(.cloud, ShapeGenerator.cloud(in: box), box)
        }
        if detectSpeechBubble(points, box) {
            return polyline(.speechBubble, ShapeGenerator.speechBubble(in: box), box)
        }

        // Smooth, round strokes are an ellipse regardless of corner count. The
        // threshold sits below a hexagon's radius variation (~0.05) so polygons
        // aren't swallowed.
        if circularity(points, box) < 0.035 {
            return ShapeRecognition(shape: .ellipse, bounds: box, vertices: [])
        }

        let corners = max(simplified.count - 1, 0)
        switch corners {
        case 3: return polyline(.triangle, Array(simplified.prefix(3)), box)
        case 4: return ShapeRecognition(shape: rectangleOrDiamond(simplified, box), bounds: box, vertices: [])
        case 5: return polyline(.pentagon, ShapeGenerator.regularPolygon(sides: 5, in: box), box)
        case 6: return polyline(.hexagon, ShapeGenerator.regularPolygon(sides: 6, in: box), box)
        default: return ShapeRecognition(shape: .ellipse, bounds: box, vertices: [])
        }
    }

    private static func polyline(
        _ shape: RecognizedShape,
        _ vertices: [Point],
        _ box: BoundingBox
    ) -> ShapeRecognition {
        ShapeRecognition(shape: shape, bounds: box, vertices: vertices)
    }

    // MARK: Feature detectors

    /// A star alternates far "tips" and near "valleys" around its centre.
    private static func detectStar(_ simplified: [Point], _: BoundingBox) -> Bool {
        let vertices = Array(simplified.dropLast()) // drop the closing duplicate
        guard vertices.count >= 8, vertices.count <= 14 else { return false }
        let c = centroid(vertices)
        let radii = vertices.map { $0.distance(to: c) }
        let mean = radii.reduce(0, +) / Double(radii.count)
        guard mean > 0 else { return false }
        // Deep, regular alternation: valleys well inside the tips.
        guard (radii.min() ?? 0) / (radii.max() ?? 1) < 0.7 else { return false }
        var alternations = 0
        for i in 0 ..< radii.count {
            let a = radii[i] - mean
            let b = radii[(i + 1) % radii.count] - mean
            if a * b < 0 { alternations += 1 }
        }
        return alternations >= 8
    }

    /// A heart has two top lobes with a central notch dipping down between them.
    private static func detectHeart(_ points: [Point], _ box: BoundingBox) -> Bool {
        let cx = (box.minX + box.maxX) / 2
        let lobeTop = { (xs: [Point]) -> Double? in xs.map(\.y).min() }
        let left = points.filter { $0.x < cx - box.width * 0.1 }
        let right = points.filter { $0.x > cx + box.width * 0.1 }
        let center = points.filter { abs($0.x - cx) < box.width * 0.1 }
        guard let lt = lobeTop(left), let rt = lobeTop(right), let ct = lobeTop(center) else { return false }
        // Centre top dips below both lobe tops, and the lowest point is centred.
        let notch = ct - min(lt, rt) > box.height * 0.05
        let bottom = points.max { $0.y < $1.y }
        let pointed = bottom.map { abs($0.x - cx) < box.width * 0.2 } ?? false
        return notch && pointed
    }

    /// A cloud is a round, bumpy outline with many shallow lobes.
    private static func detectCloud(_ points: [Point], _: BoundingBox) -> Bool {
        let c = centroid(points)
        let radii = points.map { $0.distance(to: c) }
        guard let maxR = radii.max(), let minR = radii.min(), maxR > 0 else { return false }
        let depth = 1 - minR / maxR
        guard depth > 0.08, depth < 0.45 else { return false } // bumpy but not spiky
        // Count radial local maxima (bumps) around the perimeter.
        var bumps = 0
        let n = radii.count
        for i in 0 ..< n {
            let prev = radii[(i - 1 + n) % n], cur = radii[i], next = radii[(i + 1) % n]
            if cur >= prev, cur > next { bumps += 1 }
        }
        return bumps >= 7
    }

    /// A speech bubble is a wide rectangular body with a narrow downward tail.
    private static func detectSpeechBubble(_ points: [Point], _ box: BoundingBox) -> Bool {
        guard box.width > 0, box.height > 0 else { return false }
        let topBand = points.filter { $0.y < box.minY + box.height * 0.3 }
        let bottomBand = points.filter { $0.y > box.minY + box.height * 0.8 }
        guard !topBand.isEmpty, !bottomBand.isEmpty else { return false }
        let topSpan = (topBand.map(\.x).max() ?? 0) - (topBand.map(\.x).min() ?? 0)
        let bottomSpan = (bottomBand.map(\.x).max() ?? 0) - (bottomBand.map(\.x).min() ?? 0)
        // Rectangular top spanning most of the width, narrow tail at the bottom.
        return topSpan > box.width * 0.7 && bottomSpan < box.width * 0.5
    }

    // MARK: Geometry helpers

    private static func centroid(_ points: [Point]) -> Point {
        let n = Double(max(points.count, 1))
        let sum = points.reduce(Point.zero) { Point($0.x + $1.x, $0.y + $1.y) }
        return Point(sum.x / n, sum.y / n)
    }

    /// Coefficient of variation of the radius from the centroid (0 = perfect circle).
    private static func circularity(_ points: [Point], _: BoundingBox) -> Double {
        let c = centroid(points)
        let radii = points.map { $0.distance(to: c) }
        let mean = radii.reduce(0, +) / Double(radii.count)
        guard mean > 0 else { return .infinity }
        let variance = radii.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(radii.count)
        return variance.squareRoot() / mean
    }

    /// Decide whether four corners sit at the box corners (rectangle) or at the
    /// edge midpoints (diamond).
    private static func rectangleOrDiamond(_ vertices: [Point], _ box: BoundingBox) -> RecognizedShape {
        let midX = (box.minX + box.maxX) / 2
        let midY = (box.minY + box.maxY) / 2
        let boxCorners = [
            Point(box.minX, box.minY), Point(box.maxX, box.minY),
            Point(box.maxX, box.maxY), Point(box.minX, box.maxY)
        ]
        let edgeMids = [
            Point(midX, box.minY), Point(box.maxX, midY),
            Point(midX, box.maxY), Point(box.minX, midY)
        ]
        func score(_ targets: [Point]) -> Double {
            vertices.prefix(4).reduce(0) { sum, v in sum + (targets.map { v.distance(to: $0) }.min() ?? 0) }
        }
        return score(boxCorners) <= score(edgeMids) ? .rectangle : .diamond
    }

    /// Ramer–Douglas–Peucker polyline simplification.
    static func rdp(_ points: [Point], epsilon: Double) -> [Point] {
        guard points.count >= 3, let first = points.first, let last = points.last else { return points }
        var maxDistance = 0.0
        var index = 0
        for i in 1 ..< (points.count - 1) {
            let d = perpendicularDistance(points[i], from: first, to: last)
            if d > maxDistance { maxDistance = d; index = i }
        }
        if maxDistance > epsilon {
            let left = rdp(Array(points[0 ... index]), epsilon: epsilon)
            let right = rdp(Array(points[index ..< points.count]), epsilon: epsilon)
            return left.dropLast() + right
        }
        return [first, last]
    }

    /// Drop vertices that lie (within `epsilon`) on the segment joining their
    /// neighbours, cleaning up collinear points RDP may leave on a closed loop.
    private static func removeCollinear(_ points: [Point], epsilon: Double) -> [Point] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for i in 1 ..< (points.count - 1)
            where perpendicularDistance(points[i], from: result.last!, to: points[i + 1]) > epsilon {
            result.append(points[i])
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func perpendicularDistance(_ p: Point, from a: Point, to b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return p.distance(to: a) }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        let proj = Point(a.x + t * dx, a.y + t * dy)
        return p.distance(to: proj)
    }
}
