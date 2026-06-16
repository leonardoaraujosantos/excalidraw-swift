import CoreGraphics
import ExcalidrawMath
import ExcalidrawMetal
import ExcalidrawModel
import ExcalidrawRender
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Headless CPU-vs-GPU rendering benchmark, surfaced in-app via
/// `RendererBenchmarkView` so the numbers can be read on the device screen
/// (not just the Xcode console). Pure logic — no SwiftUI — so it is unit
/// testable; mirrors the on-device XCTest benchmark.
public enum RendererBenchmark {
    /// One row of the results table: a scene description plus CPU/Metal frame
    /// times and the Metal phase breakdown.
    public struct Row: Identifiable, Sendable {
        public let id = UUID()
        public let label: String
        public let count: Int
        public let cpuMs: Double
        /// `nil` when Metal is unavailable on this device.
        public let metalMs: Double?
        /// Direct-to-drawable cost: the GPU frame with no read-back / CG
        /// compositing (what an on-screen present pays, minus the async present).
        public let metalDirectMs: Double?
        /// Editor hybrid cost: the direct GPU frame plus the Core Graphics
        /// text/selection overlay (what the live editor canvas actually pays).
        public let hybridMs: Double?
        public let geometryMs: Double?
        public let gpuMs: Double?
        public let overlayMs: Double?

        /// CPU ÷ Metal (read-back path) — above 1 means Metal is faster.
        public var ratio: Double? {
            guard let metalMs, metalMs > 0 else { return nil }
            return cpuMs / metalMs
        }

        /// CPU ÷ Metal-direct — above 1 means the direct GPU path is faster.
        public var directRatio: Double? {
            guard let metalDirectMs, metalDirectMs > 0 else { return nil }
            return cpuMs / metalDirectMs
        }

        /// CPU ÷ editor hybrid.
        public var hybridRatio: Double? {
            guard let hybridMs, hybridMs > 0 else { return nil }
            return cpuMs / hybridMs
        }
    }

    /// Which synthetic scene to build: rough `shapes` only, `mixed` (adds
    /// freedraw), or `all` component types (adds dashed, line, image and text).
    public enum SceneKind: String, Sendable {
        case shapes, mixed, all
    }

    public struct Config: Sendable {
        public let label: String
        public let kind: SceneKind
        public let count: Int

        public init(label: String, kind: SceneKind, count: Int) {
            self.label = label
            self.kind = kind
            self.count = count
        }
    }

    public static let defaultConfigs: [Config] = [
        Config(label: "shapes", kind: .shapes, count: 1500),
        Config(label: "mixed", kind: .mixed, count: 1500),
        Config(label: "all", kind: .all, count: 500),
        Config(label: "all", kind: .all, count: 1500)
    ]

    /// Whether the GPU backend can be measured on this device.
    public static var metalAvailable: Bool {
        MetalSceneRenderer.isSupported
    }

    /// Run every config and return the result rows. Renders off-screen at
    /// `width × height`, warming each renderer once (shader compile + geometry
    /// cache) before timing `iterations` frames.
    public static func run(
        width: Int = 1200, height: Int = 800,
        iterations: Int = 5, configs: [Config] = defaultConfigs
    ) -> [Row] {
        let size = CGSize(width: width, height: height)
        let viewport = Viewport()
        let cg = SceneRenderer()
        let metal = MetalSceneRenderer()

        func context() -> CGContext {
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
        }

        return configs.map { config in
            let scene = syntheticScene(count: config.count, kind: config.kind)
            let gpuHandled = Set(scene.visibleElements.filter { SceneGeometry.isGPUHandled($0) }.map(\.id))

            let cgCtx = context()
            cg.render(scene, in: cgCtx, viewport: viewport, size: size) // warm
            let cpuMs = milliseconds(iterations) {
                cg.render(scene, in: cgCtx, viewport: viewport, size: size)
            }

            var metalMs: Double?
            var metalDirectMs: Double?
            var hybridMs: Double?
            var geometryMs: Double?
            var gpuMs: Double?
            var overlayMs: Double?
            if let metal {
                let metalCtx = context()
                metal.render(scene, in: metalCtx, viewport: viewport, size: size) // warm shader + caches
                metalMs = milliseconds(iterations) {
                    metal.render(scene, in: metalCtx, viewport: viewport, size: size)
                }
                // Direct-to-drawable cost: GPU frame with no read-back / CG passes.
                metal.renderDirectFrame(
                    scene: scene, viewport: viewport, size: size, theme: .light,
                    pixelWidth: width, pixelHeight: height
                )
                metalDirectMs = milliseconds(iterations) {
                    metal.renderDirectFrame(
                        scene: scene, viewport: viewport, size: size, theme: .light,
                        pixelWidth: width, pixelHeight: height
                    )
                }
                // Editor hybrid: direct GPU frame + the CG text/selection overlay.
                let overlayCtx = context()
                hybridMs = milliseconds(iterations) {
                    metal.renderDirectFrame(
                        scene: scene, viewport: viewport, size: size, theme: .light,
                        pixelWidth: width, pixelHeight: height
                    )
                    cg.render(
                        scene, in: overlayCtx, viewport: viewport, size: size,
                        theme: .light, skipping: gpuHandled, fillBackground: false
                    )
                }
                let phases = metal.renderTimed(scene, in: context(), viewport: viewport, size: size)
                geometryMs = phases.geometryMs
                gpuMs = phases.gpuMs
                overlayMs = phases.overlayMs
            }

            return Row(
                label: config.label, count: config.count, cpuMs: cpuMs,
                metalMs: metalMs, metalDirectMs: metalDirectMs, hybridMs: hybridMs,
                geometryMs: geometryMs, gpuMs: gpuMs, overlayMs: overlayMs
            )
        }
    }

    private static func milliseconds(_ iterations: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations {
            body()
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
    }

    /// A grid of synthetic elements. `.shapes` is rough shapes only; `.mixed`
    /// adds freedraw; `.all` exercises every component type (dashed rectangle,
    /// line, image and text too).
    static func syntheticScene(count: Int, kind: SceneKind) -> Scene {
        let perRow = Int(Double(count).squareRoot().rounded(.up))
        let cell = 90.0
        let buckets = switch kind {
        case .shapes: 4
        case .mixed: 5
        case .all: 8
        }
        var elements: [ExcalidrawElement] = []
        for i in 0 ..< count {
            var b = BaseProperties(id: "e\(i)")
            b.x = Double(i % perRow) * cell + 10
            b.y = Double(i / perRow) * cell + 10
            b.width = 70; b.height = 60; b.seed = i + 1; b.strokeColor = "#1e1e1e"
            elements.append(element(index: i, bucket: i % buckets, base: b))
        }
        let files = ["bench-img": BinaryFileData(
            mimeType: "image/png", id: "bench-img", dataURL: solidImageDataURL, created: 0
        )]
        return Scene(elements: elements, files: kind == .all ? files : [:])
    }

    private static func element(index _: Int, bucket: Int, base b: BaseProperties) -> ExcalidrawElement {
        var b = b
        switch bucket {
        case 0:
            b.backgroundColor = "#ffc9c9"; b.fillStyle = .hachure
            return ExcalidrawElement(base: b, kind: .rectangle)
        case 1:
            b.backgroundColor = "#a5d8ff"; b.fillStyle = .crossHatch
            return ExcalidrawElement(base: b, kind: .ellipse)
        case 2:
            b.backgroundColor = "#b2f2bb"; b.fillStyle = .solid
            return ExcalidrawElement(base: b, kind: .diamond)
        case 3:
            let pts = [Point(0, 0), Point(70, 20), Point(20, 60), Point(70, 60)]
            return ExcalidrawElement(base: b, kind: .arrow(ArrowProperties(points: pts, endArrowhead: .arrow)))
        case 4:
            let pts = (0 ..< 60).map { j in Point(Double(j % 70), Double((j * 11) % 60)) }
            return ExcalidrawElement(base: b, kind: .freedraw(FreedrawProperties(points: pts)))
        case 5:
            b.strokeStyle = .dashed
            return ExcalidrawElement(base: b, kind: .rectangle)
        case 6:
            return ExcalidrawElement(base: b, kind: .image(ImageProperties(fileId: "bench-img")))
        default:
            return ExcalidrawElement(base: b, kind: .text(TextProperties(fontSize: 16, text: "Label")))
        }
    }

    /// A tiny solid-color PNG `data:` URL for the benchmark's image elements.
    static let solidImageDataURL: String = {
        let side = 16
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }
        ctx.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = ctx.makeImage() else { return "" }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return ""
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return "data:image/png;base64," + (data as Data).base64EncodedString()
    }()
}
