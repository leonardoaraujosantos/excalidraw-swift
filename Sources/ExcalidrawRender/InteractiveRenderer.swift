import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawMath
import Foundation

/// Draws the interactive overlay — selection bounding box, transform handles,
/// and the live box-selection marquee — on top of the static scene. Mirrors
/// `interactiveScene.ts`. Handles are sized in view pixels (divided by zoom) so
/// they stay a constant on-screen size.
public enum InteractiveRenderer {
    private static let accent = CGColor(red: 0.42, green: 0.51, blue: 0.96, alpha: 1) // Excalidraw violet

    private static let snapColor = CGColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 0.9) // red guide

    public static func render(
        selectionBounds: BoundingBox?,
        handles: [Point],
        rotationHandle: Point?,
        selectionRect: BoundingBox?,
        in ctx: CGContext,
        viewport: Viewport,
        size: CGSize = .zero,
        snapLinesX: [Double] = [],
        snapLinesY: [Double] = [],
        linearPoints: [Point] = [],
        linearMidpoints: [Point] = [],
        handleSizePx: Double = 8
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.scaleBy(x: viewport.zoom, y: viewport.zoom)
        ctx.translateBy(x: viewport.scrollX, y: viewport.scrollY)

        let lineWidth = 1 / viewport.zoom
        let handleSize = handleSizePx / viewport.zoom

        // Snap guide lines spanning the visible canvas.
        if !snapLinesX.isEmpty || !snapLinesY.isEmpty, size != .zero {
            let topLeft = viewport.viewToScene(Point(0, 0))
            let bottomRight = viewport.viewToScene(Point(size.width, size.height))
            ctx.setStrokeColor(snapColor)
            ctx.setLineWidth(lineWidth)
            for x in snapLinesX {
                ctx.move(to: CGPoint(x: x, y: topLeft.y))
                ctx.addLine(to: CGPoint(x: x, y: bottomRight.y))
            }
            for y in snapLinesY {
                ctx.move(to: CGPoint(x: topLeft.x, y: y))
                ctx.addLine(to: CGPoint(x: bottomRight.x, y: y))
            }
            ctx.strokePath()
        }

        if let rect = selectionRect {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(lineWidth)
            ctx.setLineDash(phase: 0, lengths: [4 / viewport.zoom, 4 / viewport.zoom])
            ctx.stroke(cgRect(rect))
            ctx.setFillColor(accent.copy(alpha: 0.08)!)
            ctx.fill(cgRect(rect))
            ctx.setLineDash(phase: 0, lengths: [])
        }

        if let bounds = selectionBounds {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(lineWidth)
            ctx.stroke(cgRect(bounds))

            if let rotationHandle {
                ctx.move(to: CGPoint(x: (bounds.minX + bounds.maxX) / 2, y: bounds.minY))
                ctx.addLine(to: CGPoint(x: rotationHandle.x, y: rotationHandle.y))
                ctx.strokePath()
                drawCircleHandle(rotationHandle, size: handleSize, in: ctx)
            }
            for handle in handles {
                drawSquareHandle(handle, size: handleSize, in: ctx)
            }
        }

        // Linear point-edit handles: filled circles at points, hollow at midpoints.
        for midpoint in linearMidpoints {
            drawCircleHandle(midpoint, size: handleSize * 0.8, in: ctx)
        }
        for point in linearPoints {
            let rect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            ctx.setFillColor(accent)
            ctx.fillEllipse(in: rect)
        }
    }

    private static func drawSquareHandle(_ p: Point, size: Double, in ctx: CGContext) {
        let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.setStrokeColor(accent)
        ctx.stroke(rect)
    }

    private static func drawCircleHandle(_ p: Point, size: Double, in ctx: CGContext) {
        let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(accent)
        ctx.strokeEllipse(in: rect)
    }

    private static func cgRect(_ b: BoundingBox) -> CGRect {
        CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height)
    }
}
