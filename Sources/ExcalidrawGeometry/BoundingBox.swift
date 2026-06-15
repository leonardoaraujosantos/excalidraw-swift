import ExcalidrawMath
import Foundation

/// Axis-aligned bounding box in scene coordinates.
///
/// The foundation for culling, hit-testing early-outs, and multi-select bounds
/// (see `packages/element/src/bounds.ts`). Rotated/curve-aware bounds arrive in
/// Phase 1.
public struct BoundingBox: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    /// Smallest box enclosing a set of points. Returns `nil` for an empty input.
    public init?(points: [Point]) {
        guard let first = points.first else { return nil }
        var box = BoundingBox(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points.dropFirst() {
            box.minX = Swift.min(box.minX, p.x)
            box.minY = Swift.min(box.minY, p.y)
            box.maxX = Swift.max(box.maxX, p.x)
            box.maxY = Swift.max(box.maxY, p.y)
        }
        self = box
    }

    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Union with another box.
    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            minX: Swift.min(minX, other.minX),
            minY: Swift.min(minY, other.minY),
            maxX: Swift.max(maxX, other.maxX),
            maxY: Swift.max(maxY, other.maxY)
        )
    }
}
