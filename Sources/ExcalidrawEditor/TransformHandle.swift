import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// The resize/rotate handles around a selection's bounding box.
public enum TransformHandle: String, Sendable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotation

    var movesLeft: Bool {
        self == .topLeft || self == .left || self == .bottomLeft
    }

    var movesRight: Bool {
        self == .topRight || self == .right || self == .bottomRight
    }

    var movesTop: Bool {
        self == .topLeft || self == .top || self == .topRight
    }

    var movesBottom: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }
}

public enum Transform {
    /// Minimum element size in scene units, to avoid collapsing to zero.
    static let minSize = 1.0

    /// Scene-space positions of every handle around `bounds`. `rotationOffset`
    /// is how far above the top edge the rotation handle sits.
    public static func handlePositions(
        for bounds: BoundingBox, rotationOffset: Double
    ) -> [TransformHandle: Point] {
        let midX = (bounds.minX + bounds.maxX) / 2
        let midY = (bounds.minY + bounds.maxY) / 2
        return [
            .topLeft: Point(bounds.minX, bounds.minY),
            .top: Point(midX, bounds.minY),
            .topRight: Point(bounds.maxX, bounds.minY),
            .right: Point(bounds.maxX, midY),
            .bottomRight: Point(bounds.maxX, bounds.maxY),
            .bottom: Point(midX, bounds.maxY),
            .bottomLeft: Point(bounds.minX, bounds.maxY),
            .left: Point(bounds.minX, midY),
            .rotation: Point(midX, bounds.minY - rotationOffset)
        ]
    }

    /// New bounds after dragging `handle` to `pointer`. The result is
    /// normalized (min < max) and clamped to a minimum size. `keepAspect`
    /// preserves the box ratio (corner handles); `fromCenter` resizes
    /// symmetrically about the centre.
    public static func resize(
        _ bounds: BoundingBox, handle: TransformHandle, to pointer: Point,
        keepAspect: Bool = false, fromCenter: Bool = false
    ) -> BoundingBox {
        var minX = bounds.minX, minY = bounds.minY
        var maxX = bounds.maxX, maxY = bounds.maxY
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2

        if handle.movesLeft { minX = pointer.x }
        if handle.movesRight { maxX = pointer.x }
        if handle.movesTop { minY = pointer.y }
        if handle.movesBottom { maxY = pointer.y }

        if fromCenter {
            if handle.movesLeft { maxX = 2 * centerX - minX }
            if handle.movesRight { minX = 2 * centerX - maxX }
            if handle.movesTop { maxY = 2 * centerY - minY }
            if handle.movesBottom { minY = 2 * centerY - maxY }
        }

        var result = BoundingBox(
            minX: Swift.min(minX, maxX), minY: Swift.min(minY, maxY),
            maxX: Swift.max(minX, maxX), maxY: Swift.max(minY, maxY)
        )

        if keepAspect, bounds.width != 0, bounds.height != 0 {
            result = applyAspect(result, original: bounds, handle: handle, fromCenter: fromCenter)
        }
        return clampMinSize(result)
    }

    /// Map an element from `old` bounds into `new` bounds, scaling position,
    /// size, and (for linear/freedraw) its points proportionally.
    public static func scale(
        _ element: ExcalidrawElement, from old: BoundingBox, to new: BoundingBox
    ) -> ExcalidrawElement {
        let sx = old.width == 0 ? 1 : new.width / old.width
        let sy = old.height == 0 ? 1 : new.height / old.height
        var e = element
        e.base.x = new.minX + (element.base.x - old.minX) * sx
        e.base.y = new.minY + (element.base.y - old.minY) * sy
        e.base.width = element.base.width * sx
        e.base.height = element.base.height * sy

        func scalePoints(_ pts: [Point]) -> [Point] {
            pts.map { Point($0.x * sx, $0.y * sy) }
        }
        switch e.kind {
        case var .line(p): p.points = scalePoints(p.points); e.kind = .line(p)
        case var .arrow(p): p.points = scalePoints(p.points); e.kind = .arrow(p)
        case var .freedraw(p): p.points = scalePoints(p.points); e.kind = .freedraw(p)
        case var .text(p):
            // Text grows/shrinks with the box: scale the font by the height factor.
            p.fontSize *= abs(sy)
            e.kind = .text(p)
        default: break
        }
        return e
    }

    /// Translate an element by `(dx, dy)`.
    public static func translate(_ element: ExcalidrawElement, dx: Double, dy: Double) -> ExcalidrawElement {
        var e = element
        e.base.x += dx
        e.base.y += dy
        return e
    }

    /// Rotation angle (radians) for a rotation-handle drag, with the handle
    /// directly above the centre meaning angle 0. `snap` constrains to 15°.
    public static func rotationAngle(center: Point, pointer: Point, snap: Bool) -> Double {
        var angle = atan2(pointer.y - center.y, pointer.x - center.x) + .pi / 2
        angle = Angle.normalizeRadians(angle)
        if snap {
            let step = Double.pi / 12 // 15°
            angle = (angle / step).rounded() * step
        }
        return angle
    }

    private static func applyAspect(
        _ box: BoundingBox, original: BoundingBox, handle: TransformHandle, fromCenter: Bool
    ) -> BoundingBox {
        let ratio = original.width / original.height
        // Drive the smaller relative change from the larger one.
        let scaleX = box.width / original.width
        let scaleY = box.height / original.height
        let scale = Swift.max(abs(scaleX), abs(scaleY))
        let newWidth = original.width * scale
        let newHeight = newWidth / ratio

        var minX = box.minX, minY = box.minY, maxX = box.maxX, maxY = box.maxY
        if fromCenter {
            let cx = (original.minX + original.maxX) / 2
            let cy = (original.minY + original.maxY) / 2
            minX = cx - newWidth / 2; maxX = cx + newWidth / 2
            minY = cy - newHeight / 2; maxY = cy + newHeight / 2
        } else {
            // Anchor the corner opposite the dragged handle.
            if handle.movesRight { maxX = minX + newWidth } else { minX = maxX - newWidth }
            if handle.movesBottom { maxY = minY + newHeight } else { minY = maxY - newHeight }
        }
        return BoundingBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private static func clampMinSize(_ box: BoundingBox) -> BoundingBox {
        var box = box
        if box.width < minSize { box.maxX = box.minX + minSize }
        if box.height < minSize { box.maxY = box.minY + minSize }
        return box
    }
}
