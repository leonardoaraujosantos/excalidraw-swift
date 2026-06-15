import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Maps scene coordinates to view coordinates given the current pan/zoom.
///
/// Single source of truth for the canvas transform: render, hit-testing, and
/// snapping all derive from a `Viewport`. Mirrors the scroll/zoom model in
/// `packages/excalidraw/renderer/staticScene.ts`.
public struct Viewport: Equatable, Sendable {
    public var scrollX: Double
    public var scrollY: Double
    public var zoom: Double

    public init(scrollX: Double = 0, scrollY: Double = 0, zoom: Double = 1) {
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.zoom = zoom
    }

    public func sceneToView(_ point: Point) -> Point {
        Point((point.x + scrollX) * zoom, (point.y + scrollY) * zoom)
    }

    public func viewToScene(_ point: Point) -> Point {
        Point(point.x / zoom - scrollX, point.y / zoom - scrollY)
    }

    /// Affine transform applied to the static canvas before drawing elements.
    public var affineTransform: CGAffineTransform {
        CGAffineTransform(scaleX: zoom, y: zoom)
            .translatedBy(x: scrollX, y: scrollY)
    }
}

public enum ExcalidrawRender {
    public static let zoomRange: ClosedRange<Double> = 0.1...30
}
