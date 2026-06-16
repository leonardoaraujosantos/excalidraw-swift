import ExcalidrawModel
import Foundation

/// Viewport culling: drop elements whose (rotation-aware) bounds fall entirely
/// outside the visible region so large scenes only pay to draw what's on
/// screen. Mirrors the off-screen skip in upstream's static-scene renderer.
public enum Culling {
    /// The elements from `elements` that intersect `visible`, expanded by
    /// `margin` scene units so wide strokes near the edge aren't clipped.
    public static func visible(
        _ elements: [ExcalidrawElement], in visible: BoundingBox, margin: Double = 0
    ) -> [ExcalidrawElement] {
        let region = BoundingBox(
            minX: visible.minX - margin, minY: visible.minY - margin,
            maxX: visible.maxX + margin, maxY: visible.maxY + margin
        )
        return elements.filter { intersects(ElementGeometry.bounds($0), region) }
    }

    private static func intersects(_ a: BoundingBox, _ b: BoundingBox) -> Bool {
        a.minX <= b.maxX && a.maxX >= b.minX && a.minY <= b.maxY && a.maxY >= b.minY
    }
}
