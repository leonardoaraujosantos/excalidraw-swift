import CoreGraphics
import ExcalidrawMath
import ExcalidrawMetal
import ExcalidrawModel
import ExcalidrawRender
import Foundation

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
        public let geometryMs: Double?
        public let gpuMs: Double?
        public let overlayMs: Double?

        /// CPU ÷ Metal — above 1 means Metal is faster.
        public var ratio: Double? {
            guard let metalMs, metalMs > 0 else { return nil }
            return cpuMs / metalMs
        }
    }

    public struct Config: Sendable {
        public let label: String
        public let shapesOnly: Bool
        public let count: Int

        public init(label: String, shapesOnly: Bool, count: Int) {
            self.label = label
            self.shapesOnly = shapesOnly
            self.count = count
        }
    }

    public static let defaultConfigs: [Config] = [
        Config(label: "shapes", shapesOnly: true, count: 500),
        Config(label: "shapes", shapesOnly: true, count: 1500),
        Config(label: "mixed", shapesOnly: false, count: 500),
        Config(label: "mixed", shapesOnly: false, count: 1500)
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
            let scene = syntheticScene(count: config.count, shapesOnly: config.shapesOnly)

            let cgCtx = context()
            cg.render(scene, in: cgCtx, viewport: viewport, size: size) // warm
            let cpuMs = milliseconds(iterations) {
                cg.render(scene, in: cgCtx, viewport: viewport, size: size)
            }

            var metalMs: Double?
            var geometryMs: Double?
            var gpuMs: Double?
            var overlayMs: Double?
            if let metal {
                let metalCtx = context()
                metal.render(scene, in: metalCtx, viewport: viewport, size: size) // warm shader + caches
                metalMs = milliseconds(iterations) {
                    metal.render(scene, in: metalCtx, viewport: viewport, size: size)
                }
                let phases = metal.renderTimed(scene, in: context(), viewport: viewport, size: size)
                geometryMs = phases.geometryMs
                gpuMs = phases.gpuMs
                overlayMs = phases.overlayMs
            }

            return Row(
                label: config.label, count: config.count, cpuMs: cpuMs,
                metalMs: metalMs, geometryMs: geometryMs, gpuMs: gpuMs, overlayMs: overlayMs
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

    /// Grid of mixed elements. `shapesOnly` keeps only the rough shape kinds;
    /// otherwise every fifth element is a freedraw stroke. Both are now
    /// GPU-tessellated, so `mixed` mainly adds freehand-outline triangles.
    static func syntheticScene(count: Int, shapesOnly: Bool) -> Scene {
        let perRow = Int(Double(count).squareRoot().rounded(.up))
        let cell = 90.0
        let kinds = shapesOnly ? 4 : 5
        var elements: [ExcalidrawElement] = []
        for i in 0 ..< count {
            var b = BaseProperties(id: "e\(i)")
            b.x = Double(i % perRow) * cell + 10
            b.y = Double(i / perRow) * cell + 10
            b.width = 70; b.height = 60; b.seed = i + 1; b.strokeColor = "#1e1e1e"
            switch i % kinds {
            case 0:
                b.backgroundColor = "#ffc9c9"; b.fillStyle = .hachure
                elements.append(ExcalidrawElement(base: b, kind: .rectangle))
            case 1:
                b.backgroundColor = "#a5d8ff"; b.fillStyle = .crossHatch
                elements.append(ExcalidrawElement(base: b, kind: .ellipse))
            case 2:
                b.backgroundColor = "#b2f2bb"; b.fillStyle = .solid
                elements.append(ExcalidrawElement(base: b, kind: .diamond))
            case 3:
                let pts = [Point(0, 0), Point(70, 20), Point(20, 60), Point(70, 60)]
                elements.append(ExcalidrawElement(
                    base: b, kind: .arrow(ArrowProperties(points: pts, endArrowhead: .arrow))
                ))
            default:
                let pts = (0 ..< 200).map { j in Point(Double(j % 70), Double((j * 7) % 60)) }
                elements.append(ExcalidrawElement(base: b, kind: .freedraw(FreedrawProperties(points: pts))))
            }
        }
        return Scene(elements: elements)
    }
}
