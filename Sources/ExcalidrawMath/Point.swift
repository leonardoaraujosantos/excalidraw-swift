import Foundation

/// A 2D point in scene coordinates.
///
/// Mirrors Excalidraw's `LocalPoint`/`GlobalPoint` tuple `[number, number]`
/// (see `packages/math/src/point.ts`). Expanded incrementally in Phase 1.
public struct Point: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    /// Euclidean distance to another point.
    public func distance(to other: Point) -> Double {
        (self - other).magnitude
    }

    /// Vector magnitude treating the point as a vector from the origin.
    public var magnitude: Double {
        (x * x + y * y).squareRoot()
    }

    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(lhs.x + rhs.x, lhs.y + rhs.y)
    }
}

public enum ExcalidrawMath {
    /// Numerical tolerance used throughout geometry, matching upstream `PRECISION`.
    public static let precision = 1e-5
}
