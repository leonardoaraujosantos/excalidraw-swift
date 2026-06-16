import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import ExcalidrawRender
import Foundation
import Metal

/// A Metal-backed `SceneRendering`. Rough shapes (rectangle, diamond, ellipse,
/// line, arrow) are tessellated and rasterized on the GPU with 4× multisampling;
/// everything else — background, grid, text, images, frames,
/// embeddables, dashed strokes and frame-clipped children — is drawn by a
/// shared Core Graphics `SceneRenderer` in an overlay pass.
///
/// Compositing order per frame: (1) background + grid via CG, (2) the GPU shape
/// image, (3) the remaining CG elements on top. The GPU image and CG passes both
/// land in the caller's y-down context, so output matches `SceneRenderer` and a
/// device with no Metal support transparently uses the CG path via `make()`.
public final class MetalSceneRenderer: SceneRendering {
    private let gpu: MetalRenderContext
    private let cgRenderer: SceneRenderer
    private let shapeCache: ShapeCache
    /// Persists tessellated vertices across frames so steady-state pan/zoom only
    /// re-tessellates elements that actually changed (the dominant per-frame
    /// cost). Lives on the renderer, which outlives individual frames.
    private let geometryCache = GeometryCache()

    /// Create a Metal renderer, or `nil` when Metal is unavailable on this host
    /// (caller falls back to `SceneRenderer`). Shares one `ShapeCache` between
    /// the GPU tessellation and the CG overlay so drawables are generated once.
    public init?(shapeCache: ShapeCache = ShapeCache()) {
        guard let gpu = MetalRenderContext() else { return nil }
        self.gpu = gpu
        self.shapeCache = shapeCache
        cgRenderer = SceneRenderer(shapeCache: shapeCache)
    }

    /// Whether a Metal renderer can be constructed on this host.
    public static var isSupported: Bool {
        MetalRenderContext.isSupported
    }

    public func render(
        _ scene: Scene, in ctx: CGContext, viewport: Viewport, size: CGSize,
        theme: Theme, clip: BoundingBox?, skipping: Set<String>, fillBackground: Bool
    ) {
        let geometry = SceneGeometry(
            scene: scene, theme: theme, skipping: skipping,
            visibleRegion: Self.visibleRegion(viewport: viewport, size: size),
            shapeCache: shapeCache, geometryCache: geometryCache
        )

        // The grid (rare, debug aid) still needs Core Graphics. When it's on, fall
        // back to the CG background+grid pass and clear the GPU layer transparent;
        // otherwise the GPU paints the background as its clear color (one fewer
        // CG pass), and still paints it when there are no shapes.
        let gridOn = scene.appState.gridModeEnabled == true
        let gpuBackground = fillBackground && !gridOn

        // 1. Background + grid via CG only when the grid is enabled.
        if fillBackground, gridOn {
            let allIDs = Set(scene.visibleElements.map(\.id))
            cgRenderer.render(
                scene, in: ctx, viewport: viewport, size: size, theme: theme,
                clip: clip, skipping: allIDs, fillBackground: true
            )
        }

        // 2. GPU shape image (over the background clear when we own it),
        //    composited upright into the y-down context.
        let clearColor = gpuBackground ? Self.backgroundClear(scene, theme: theme) : Self.transparentClear
        if let image = gpuImage(geometry, viewport: viewport, size: size, ctx: ctx, clearColor: clearColor) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }

        // 3. Remaining elements (text/images/frames/embeddables/etc.) over the top.
        cgRenderer.render(
            scene, in: ctx, viewport: viewport, size: size, theme: theme,
            clip: clip, skipping: skipping.union(geometry.handledIDs), fillBackground: false
        )
    }

    /// Per-phase wall-clock breakdown of one frame, for the on-device renderer
    /// benchmark. Renders the same three passes as `render` while timing each.
    public struct PhaseTimings: Sendable {
        public var geometryMs = 0.0
        public var backgroundMs = 0.0
        public var gpuMs = 0.0
        public var overlayMs = 0.0
    }

    public func renderTimed(
        _ scene: Scene, in ctx: CGContext, viewport: Viewport, size: CGSize, theme: Theme = .light
    ) -> PhaseTimings {
        func ms(_ body: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        }
        var timings = PhaseTimings()
        var geometry: SceneGeometry?
        timings.geometryMs = ms {
            geometry = SceneGeometry(
                scene: scene, theme: theme,
                visibleRegion: Self.visibleRegion(viewport: viewport, size: size),
                shapeCache: shapeCache, geometryCache: geometryCache
            )
        }
        guard let geometry else { return timings }

        // The background folds into the GPU clear (gridless path), so the CG
        // background phase is effectively zero here.
        let gridOn = scene.appState.gridModeEnabled == true
        if gridOn {
            let allIDs = Set(scene.visibleElements.map(\.id))
            timings.backgroundMs = ms {
                cgRenderer.render(
                    scene, in: ctx, viewport: viewport, size: size, theme: theme,
                    clip: nil, skipping: allIDs, fillBackground: true
                )
            }
        }
        let clearColor = gridOn ? Self.transparentClear : Self.backgroundClear(scene, theme: theme)
        var image: CGImage?
        timings.gpuMs = ms {
            image = gpuImage(geometry, viewport: viewport, size: size, ctx: ctx, clearColor: clearColor)
        }
        if let image {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
        timings.overlayMs = ms {
            cgRenderer.render(
                scene, in: ctx, viewport: viewport, size: size, theme: theme,
                clip: nil, skipping: geometry.handledIDs, fillBackground: false
            )
        }
        return timings
    }

    private func gpuImage(
        _ geometry: SceneGeometry, viewport: Viewport, size: CGSize,
        ctx: CGContext, clearColor: MTLClearColor
    ) -> CGImage? {
        // Match the GPU texture to the context's backing resolution so shapes
        // stay crisp at any zoom / display scale.
        let pixelWidth = ctx.width > 0 ? ctx.width : Int(size.width.rounded())
        let pixelHeight = ctx.height > 0 ? ctx.height : Int(size.height.rounded())
        let transform = Self.clipTransform(viewport: viewport, size: size)
        return gpu.image(
            vertices: geometry.vertices, transform: transform, clearColor: clearColor,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight
        )
    }

    static let transparentClear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// The themed background color as a Metal clear color (mirrors
    /// `SceneRenderer`'s background fill).
    static func backgroundClear(_ scene: Scene, theme: Theme) -> MTLClearColor {
        let cg: CGColor = if let userBackground = scene.appState.viewBackgroundColor,
                             let parsed = ColorParser.cgColor(userBackground) {
            ThemeFilter.apply(parsed, theme: theme)
        } else {
            ColorParser.cgColor(theme == .dark ? "#121212" : "#ffffff")
                ?? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        guard let c = cg.components, c.count >= 3 else {
            return MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        return MTLClearColor(
            red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]),
            alpha: Double(c.count >= 4 ? c[3] : 1)
        )
    }

    /// The visible scene rectangle for the current viewport, used to cull the
    /// GPU geometry to what's on screen.
    static func visibleRegion(viewport: Viewport, size: CGSize) -> BoundingBox {
        let topLeft = viewport.viewToScene(Point(0, 0))
        let bottomRight = viewport.viewToScene(Point(size.width, size.height))
        return BoundingBox(
            minX: topLeft.x, minY: topLeft.y, maxX: bottomRight.x, maxY: bottomRight.y
        )
    }

    /// Scene → clip-space affine. `view = (scene + scroll) * zoom`; clip maps the
    /// point rect `[0, size]` to `[-1, 1]` with y flipped (clip is y-up).
    static func clipTransform(viewport: Viewport, size: CGSize) -> MetalRenderContext.Transform {
        let halfW = Float(size.width / 2), halfH = Float(size.height / 2)
        let zoom = Float(viewport.zoom)
        let scrollX = Float(viewport.scrollX), scrollY = Float(viewport.scrollY)
        return MetalRenderContext.Transform(
            ax: zoom / halfW,
            bx: scrollX * zoom / halfW - 1,
            cy: -zoom / halfH,
            dy: 1 - scrollY * zoom / halfH
        )
    }
}
