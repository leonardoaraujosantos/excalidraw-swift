import ExcalidrawMath
import Foundation

/// A shape a freehand stroke can be snapped to.
public enum RecognizedShape: Equatable, Sendable {
    case line, rectangle, diamond, ellipse, triangle
}

/// The result of recognizing a freehand stroke: the shape, its bounding box,
/// and (for line/triangle) the concrete vertices to build a polyline from.
public struct ShapeRecognition: Equatable, Sendable {
    public let shape: RecognizedShape
    public let bounds: BoundingBox
    public let vertices: [Point]
}

/// Recognizes a freehand stroke as a clean geometric shape (square/rectangle,
/// circle/ellipse, triangle, diamond, or straight line) so it can be replaced
/// by a perfect figure. Uses Ramer–Douglas–Peucker simplification to count the
/// dominant corners, then classifies by corner count and placement.
public enum ShapeRecognizer {
    /// Recognize `points` (a freehand stroke), or `nil` if it doesn't match a
    /// known shape. `points` may be in any coordinate space; `bounds`/`vertices`
    /// come back in the same space.
    public static func recognize(_ points: [Point]) -> ShapeRecognition? {
        guard points.count >= 2, let box = BoundingBox(points: points) else { return nil }
        let diagonal = (box.width * box.width + box.height * box.height).squareRoot()
        guard diagonal > 1 else { return nil }

        let closed = points.count >= 3 && (points.first!.distance(to: points.last!) < diagonal * 0.25)
        let simplified = rdp(points, epsilon: diagonal * 0.08)

        if !closed {
            // A nearly straight open stroke → a line.
            return simplified.count <= 2
                ? ShapeRecognition(shape: .line, bounds: box, vertices: [points.first!, points.last!])
                : nil
        }

        // Closed loop: RDP keeps both (near-coincident) endpoints, so the corner
        // count is one less than the simplified vertex count.
        let corners = max(simplified.count - 1, 0)
        switch corners {
        case 3:
            return ShapeRecognition(shape: .triangle, bounds: box, vertices: Array(simplified.prefix(3)))
        case 4:
            return ShapeRecognition(shape: rectangleOrDiamond(simplified, box), bounds: box, vertices: [])
        case 5...:
            return ShapeRecognition(shape: .ellipse, bounds: box, vertices: [])
        default:
            return nil
        }
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
            vertices.prefix(4).reduce(0) { sum, v in
                sum + (targets.map { v.distance(to: $0) }.min() ?? 0)
            }
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

    private static func perpendicularDistance(_ p: Point, from a: Point, to b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return p.distance(to: a) }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        let proj = Point(a.x + t * dx, a.y + t * dy)
        return p.distance(to: proj)
    }
}
