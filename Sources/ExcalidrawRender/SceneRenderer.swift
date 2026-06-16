import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation
import FreehandKit
import RoughKit

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
    public static let zoomRange: ClosedRange<Double> = 0.1 ... 30
}

/// Renders a scene's static content (background, grid, elements) into a
/// `CGContext`. Assumes a y-down context (SwiftUI `Canvas` via `withCGContext`,
/// a UIKit view, or `UIGraphicsImageRenderer`). Ports the flow of
/// `packages/excalidraw/renderer/staticScene.ts`.
public final class SceneRenderer {
    private let shapeCache: ShapeCache
    private let imageDecoder: ImageDecoder

    public init(shapeCache: ShapeCache = ShapeCache(), imageDecoder: ImageDecoder = ImageDecoder()) {
        self.shapeCache = shapeCache
        self.imageDecoder = imageDecoder
    }

    private var theme: Theme = .light

    /// Parse a colour string and apply the current theme filter.
    private func themed(_ string: String) -> CGColor {
        let base = ColorParser.cgColor(string) ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        return ThemeFilter.apply(base, theme: theme)
    }

    public func render(_ scene: Scene, in ctx: CGContext, viewport: Viewport, size: CGSize, theme: Theme = .light) {
        self.theme = theme
        // Background: a user-set colour is theme-filtered (white→dark); the
        // default canvas colour is used directly so it isn't double-inverted.
        let background: CGColor = if let userBackground = scene.appState.viewBackgroundColor {
            themed(userBackground)
        } else {
            ColorParser.cgColor(theme == .dark ? "#121212" : "#ffffff")
                ?? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        ctx.setFillColor(background)
        ctx.fill(CGRect(origin: .zero, size: size))

        ctx.saveGState()
        ctx.scaleBy(x: viewport.zoom, y: viewport.zoom)
        ctx.translateBy(x: viewport.scrollX, y: viewport.scrollY)

        if scene.appState.gridModeEnabled == true {
            drawGrid(in: ctx, viewport: viewport, size: size)
        }

        // Frame bounds in scene coordinates, for clipping their children.
        var frameBounds: [String: CGRect] = [:]
        for element in scene.visibleElements where isFrame(element) {
            let b = element.base
            frameBounds[element.id] = CGRect(x: b.x, y: b.y, width: b.width, height: b.height)
        }

        for element in scene.visibleElements {
            drawElement(element, in: ctx, files: scene.files, frameBounds: frameBounds)
        }
        ctx.restoreGState()
    }

    private func isFrame(_ element: ExcalidrawElement) -> Bool {
        switch element.kind {
        case .frame, .magicframe: true
        default: false
        }
    }

    private func drawElement(
        _ element: ExcalidrawElement, in ctx: CGContext,
        files: [String: BinaryFileData], frameBounds: [String: CGRect]
    ) {
        let base = element.base
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if isFrame(element) {
            drawFrame(element, in: ctx)
            return
        }
        // Clip elements that belong to a frame to that frame's bounds.
        if let frameId = base.frameId, let rect = frameBounds[frameId] {
            ctx.clip(to: rect)
        }

        ctx.translateBy(x: base.x, y: base.y)
        // Rotate about the element's local centre.
        let cx = base.width / 2, cy = base.height / 2
        if base.angle != 0 {
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(base.angle))
            ctx.translateBy(x: -cx, y: -cy)
        }
        ctx.setAlpha(CGFloat(base.opacity / 100))

        switch element.kind {
        case let .text(text):
            let color = themed(base.strokeColor)
            TextLayout.draw(text, base: base, in: ctx, color: color)
        case let .image(image):
            drawImage(image, base: base, in: ctx, files: files)
        case let .freedraw(props):
            drawFreedraw(props, base: base, in: ctx)
        case let .arrow(props):
            if let drawable = shapeCache.drawable(for: element) {
                drawDrawable(drawable, base: base, in: ctx)
            }
            drawArrowheads(props, base: base, in: ctx)
        default:
            if let drawable = shapeCache.drawable(for: element) {
                drawDrawable(drawable, base: base, in: ctx)
            }
        }
    }

    private func drawFrame(_ element: ExcalidrawElement, in ctx: CGContext) {
        let base = element.base
        let border = ThemeFilter.apply(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1), theme: theme)
        let rect = CGRect(x: base.x, y: base.y, width: base.width, height: base.height)
        let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(border)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()

        // Name label just above the top-left corner.
        if case let .frame(name) = element.kind, let name, !name.isEmpty {
            ctx.saveGState()
            ctx.translateBy(x: base.x, y: base.y - 18)
            let text = TextProperties(fontSize: 12, text: name)
            TextLayout.draw(text, base: base, in: ctx, color: border)
            ctx.restoreGState()
        }
    }

    private func drawArrowheads(_ props: ArrowProperties, base: BaseProperties, in ctx: CGContext) {
        let pts = props.points
        guard pts.count >= 2 else { return }
        let stroke = themed(base.strokeColor)
        if let head = props.endArrowhead {
            drawArrowhead(
                at: pts[pts.count - 1], from: pts[pts.count - 2],
                head: head, base: base, color: stroke, in: ctx
            )
        }
        if let head = props.startArrowhead {
            drawArrowhead(at: pts[0], from: pts[1], head: head, base: base, color: stroke, in: ctx)
        }
    }

    private func drawArrowhead(
        at tip: Point, from prev: Point, head: Arrowhead, base: BaseProperties, color: CGColor, in ctx: CGContext
    ) {
        let dir = Vector(from: tip, origin: prev).normalized() // points toward the tip
        guard dir.magnitude > 0 else { return }
        let segLength = tip.distance(to: prev)
        let size = Swift.min(20, segLength * 0.5) + base.strokeWidth
        let angle = 25.0 * .pi / 180
        // Two barbs, rotating the reverse direction by ±angle.
        let back = Vector(-dir.u, -dir.v)
        func rotated(_ v: Vector, by a: Double) -> Vector {
            Vector(v.u * cos(a) - v.v * sin(a), v.u * sin(a) + v.v * cos(a))
        }
        let b1 = rotated(back, by: angle).scaled(by: size)
        let b2 = rotated(back, by: -angle).scaled(by: size)
        let p1 = Point(tip.x + b1.u, tip.y + b1.v)
        let p2 = Point(tip.x + b2.u, tip.y + b2.v)

        let filled = head == .triangle || head == .diamond
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p1.x, y: p1.y))
        path.addLine(to: CGPoint(x: tip.x, y: tip.y))
        path.addLine(to: CGPoint(x: p2.x, y: p2.y))
        if filled { path.closeSubpath() }
        ctx.addPath(path)
        if filled {
            ctx.setFillColor(color)
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(CGFloat(base.strokeWidth))
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokePath()
        }
    }

    private func drawDrawable(_ drawable: Drawable, base: BaseProperties, in ctx: CGContext) {
        let strokeColor = themed(base.strokeColor)
        let fillColor = drawable.options.fill.map { themed($0) }

        for set in drawable.sets {
            let path = RoughPath.cgPath(from: set.ops)
            switch set.type {
            case .fillPath:
                if let fillColor {
                    ctx.addPath(path)
                    ctx.setFillColor(fillColor)
                    ctx.fillPath()
                }
            case .fillSketch:
                if let fillColor {
                    ctx.addPath(path)
                    ctx.setStrokeColor(fillColor)
                    let weight = drawable.options.fillWeight > 0 ? drawable.options.fillWeight : base.strokeWidth / 2
                    ctx.setLineWidth(CGFloat(weight))
                    ctx.setLineDash(phase: 0, lengths: [])
                    ctx.strokePath()
                }
            case .path:
                ctx.addPath(path)
                ctx.setStrokeColor(strokeColor)
                ctx.setLineWidth(CGFloat(base.strokeWidth))
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                applyDash(drawable.options.strokeLineDash, in: ctx)
                ctx.strokePath()
            }
        }
    }

    private func drawFreedraw(_ props: FreedrawProperties, base: BaseProperties, in ctx: CGContext) {
        guard !props.points.isEmpty else { return }
        let strokeColor = themed(base.strokeColor)
        let inputs = props.points.enumerated().map { index, p in
            FreehandPoint(x: p.x, y: p.y, pressure: index < props.pressures.count ? props.pressures[index] : 0.5)
        }
        let options = FreehandOptions(strokeWidth: base.strokeWidth, simulatePressure: props.simulatePressure)
        let outline = FreehandKit.strokeOutline(inputs, options: options)
        guard let first = outline.first, outline.count > 2 else { return }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for p in outline.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(strokeColor) // perfect-freehand strokes are filled outlines
        ctx.fillPath()
    }

    private func drawImage(
        _ image: ImageProperties, base: BaseProperties, in ctx: CGContext, files: [String: BinaryFileData]
    ) {
        guard let fileId = image.fileId, let file = files[fileId],
              let fullImage = imageDecoder.image(fileId: fileId, dataURL: file.dataURL) else { return }
        // Honor a crop: draw only the cropped sub-region of the source, scaled
        // to fill the element rect. Crop is in natural-pixel, top-left coords.
        let cgImage: CGImage
        if let crop = image.crop {
            let cropRect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
            cgImage = fullImage.cropping(to: cropRect) ?? fullImage
        } else {
            cgImage = fullImage
        }
        // CGContext.draw flips images in a y-down context; flip back so it is upright.
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: base.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: rect)
        ctx.restoreGState()
    }

    private func drawGrid(in ctx: CGContext, viewport: Viewport, size: CGSize) {
        let gridSize = 20.0
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.1))
        ctx.setLineWidth(1 / viewport.zoom)
        let path = CGMutablePath()
        // Visible scene bounds.
        let topLeft = viewport.viewToScene(Point(0, 0))
        let bottomRight = viewport.viewToScene(Point(size.width, size.height))
        var x = (topLeft.x / gridSize).rounded(.down) * gridSize
        while x <= bottomRight.x {
            path.move(to: CGPoint(x: x, y: topLeft.y))
            path.addLine(to: CGPoint(x: x, y: bottomRight.y))
            x += gridSize
        }
        var y = (topLeft.y / gridSize).rounded(.down) * gridSize
        while y <= bottomRight.y {
            path.move(to: CGPoint(x: topLeft.x, y: y))
            path.addLine(to: CGPoint(x: bottomRight.x, y: y))
            y += gridSize
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

    private func applyDash(_ dash: [Double]?, in ctx: CGContext) {
        if let dash, !dash.isEmpty {
            ctx.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) })
        } else {
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }
}
