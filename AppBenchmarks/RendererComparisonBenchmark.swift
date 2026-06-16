import CoreGraphics
import ExcalidrawMath
import ExcalidrawMetal
import ExcalidrawModel
import ExcalidrawRender
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// On-device stress benchmark comparing the Core Graphics (CPU) renderer with
/// the Metal (GPU) renderer on the same scenes. App-hosted so it runs the real
/// `MetalSceneRenderer` (GPU device + shader compile + readback) in-process on a
/// real iPad/iPhone:
///
///   xcodebuild test -scheme ExcalidrawApp \
///     -destination 'platform=iOS,id=<device-udid>' \
///     -only-testing:ExcalidrawAppBenchmarks/RendererComparisonBenchmark
///
/// Read the printed `RENDERER BENCH` lines for the numbers. The test asserts
/// only that both backends produce a non-empty image (never an absolute or
/// relative wall-clock time) so it can't flake on hardware where readback
/// overhead outweighs GPU throughput at a given scene size.
final class RendererComparisonBenchmark: XCTestCase {
    private let width = 1200
    private let height = 800

    private func context() -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// A grid of mixed elements. `shapesOnly` keeps only the GPU-tessellated
    /// kinds (rect/ellipse/diamond/arrow) — the Metal best case — while the
    /// default mix adds freedraw, which the Metal path routes back to CG.
    private func syntheticScene(count: Int, shapesOnly: Bool) -> Scene {
        let perRow = Int(Double(count).squareRoot().rounded(.up))
        let cell = 90.0
        var elements: [ExcalidrawElement] = []
        let kinds = shapesOnly ? 4 : 5
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

    /// A scene exercising every component type — rectangle (solid + dashed),
    /// diamond, ellipse, line, arrow, freedraw, image and text — in proportion,
    /// so the comparison reflects a realistic mixed document. Images and text are
    /// the parts the Metal hybrid keeps partly on Core Graphics (text) or moved
    /// to the GPU (images).
    private func allTypesScene(count: Int) -> (scene: Scene, gpuHandled: Set<String>) {
        let perRow = Int(Double(count).squareRoot().rounded(.up))
        let cell = 90.0
        let imageURL = Self.solidImageDataURL
        let files = ["bench-img": BinaryFileData(
            mimeType: "image/png", id: "bench-img", dataURL: imageURL, created: 0
        )]
        var elements: [ExcalidrawElement] = []
        for i in 0 ..< count {
            var b = BaseProperties(id: "e\(i)")
            b.x = Double(i % perRow) * cell + 10
            b.y = Double(i / perRow) * cell + 10
            b.width = 70; b.height = 60; b.seed = i + 1; b.strokeColor = "#1e1e1e"
            switch i % 8 {
            case 0:
                b.backgroundColor = "#ffc9c9"; b.fillStyle = .hachure
                elements.append(ExcalidrawElement(base: b, kind: .rectangle))
            case 1:
                b.strokeStyle = .dashed
                elements.append(ExcalidrawElement(base: b, kind: .rectangle))
            case 2:
                b.backgroundColor = "#a5d8ff"; b.fillStyle = .crossHatch
                elements.append(ExcalidrawElement(base: b, kind: .ellipse))
            case 3:
                b.backgroundColor = "#b2f2bb"; b.fillStyle = .solid
                elements.append(ExcalidrawElement(base: b, kind: .diamond))
            case 4:
                let pts = [Point(0, 30), Point(70, 30)]
                elements.append(ExcalidrawElement(base: b, kind: .line(LinearProperties(points: pts))))
            case 5:
                let pts = [Point(0, 0), Point(70, 20), Point(20, 60), Point(70, 60)]
                elements.append(ExcalidrawElement(
                    base: b, kind: .arrow(ArrowProperties(points: pts, endArrowhead: .arrow))
                ))
            case 6:
                let pts = (0 ..< 60).map { j in Point(Double(j % 70), Double((j * 11) % 60)) }
                elements.append(ExcalidrawElement(base: b, kind: .freedraw(FreedrawProperties(points: pts))))
            default:
                // Alternate image and text so both are represented.
                if i % 16 == 7 {
                    elements.append(ExcalidrawElement(
                        base: b, kind: .image(ImageProperties(fileId: "bench-img"))
                    ))
                } else {
                    elements.append(ExcalidrawElement(
                        base: b, kind: .text(TextProperties(fontSize: 16, text: "Label"))
                    ))
                }
            }
        }
        let gpuHandled = Set(elements.filter { SceneGeometry.isGPUHandled($0) }.map(\.id))
        return (Scene(elements: elements, files: files), gpuHandled)
    }

    /// A tiny solid-color PNG `data:` URL for the benchmark's image elements.
    private static let solidImageDataURL: String = {
        let side = 16
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = ctx.makeImage() else { return "" }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return "" }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return "data:image/png;base64," + (data as Data).base64EncodedString()
    }()

    private func milliseconds(_ iterations: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations {
            body()
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
    }

    private func inkFraction(_ ctx: CGContext) -> Double {
        guard let data = ctx.data else { return 0 }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let total = width * height
        var ink = 0
        for i in 0 ..< total {
            let p = i * 4
            if Int(pixels[p]) + Int(pixels[p + 1]) + Int(pixels[p + 2]) < 600 { ink += 1 }
        }
        return Double(ink) / Double(total)
    }

    /// Head-to-head per frame on the same scenes: CPU (Core Graphics) vs Metal
    /// (read-back path that composites into a CGContext) vs Metal-direct (the GPU
    /// frame with no read-back / CG passes — what a present-to-drawable costs).
    /// `shapes-only` is rough shapes; `mixed` adds freedraw (also GPU-tessellated
    /// now). Asserts only that both backends paint the scene — never a wall-clock
    /// target — so it can't flake.
    func testMetalVsCoreGraphicsOnDevice() throws {
        guard let metal = MetalSceneRenderer() else {
            throw XCTSkip("No Metal device on this host")
        }
        let cg = SceneRenderer()
        let size = CGSize(width: width, height: height)
        let viewport = Viewport()

        for shapesOnly in [true, false] {
            let label = shapesOnly ? "shapes-only" : "mixed"
            for count in [500, 1500] {
                let scene = syntheticScene(count: count, shapesOnly: shapesOnly)

                let cgCtx = context()
                cg.render(scene, in: cgCtx, viewport: viewport, size: size) // warm
                let cgMs = milliseconds(5) { cg.render(scene, in: cgCtx, viewport: viewport, size: size) }

                let metalCtx = context()
                metal.render(scene, in: metalCtx, viewport: viewport, size: size) // warm shader + caches
                let metalMs = milliseconds(5) { metal.render(scene, in: metalCtx, viewport: viewport, size: size) }

                // Direct-to-drawable cost: GPU frame with no read-back / CG passes.
                metal.renderDirectFrame(
                    scene: scene, viewport: viewport, size: size, theme: .light,
                    pixelWidth: width, pixelHeight: height
                )
                let directMs = milliseconds(5) {
                    metal.renderDirectFrame(
                        scene: scene, viewport: viewport, size: size, theme: .light,
                        pixelWidth: width, pixelHeight: height
                    )
                }

                XCTAssertGreaterThan(inkFraction(cgCtx), 0.01, "\(label) n=\(count): CG drew nothing")
                XCTAssertGreaterThan(inkFraction(metalCtx), 0.01, "\(label) n=\(count): Metal drew nothing")
                print(String(
                    format: "RENDERER BENCH %-11@ n=%4d  cpu=%6.1f ms  metal=%6.1f ms (%.2fx)  "
                        + "metal-direct=%6.1f ms (%.2fx)",
                    label as NSString, count, cgMs, metalMs, cgMs / metalMs, directMs, cgMs / directMs
                ))
            }
        }
    }

    /// Comprehensive comparison on a scene with **every** component type
    /// (rectangle solid + dashed, diamond, ellipse, line, arrow, freedraw, image,
    /// text). Compares CPU, Metal read-back, Metal-direct (GPU only), and the
    /// editor **hybrid** (direct GPU frame + the Core Graphics text/selection
    /// overlay — what the live editor actually pays).
    func testAllComponentTypesOnDevice() throws {
        guard let metal = MetalSceneRenderer() else {
            throw XCTSkip("No Metal device on this host")
        }
        let cg = SceneRenderer()
        let size = CGSize(width: width, height: height)
        let viewport = Viewport()

        for count in [500, 1500] {
            let (scene, gpuHandled) = allTypesScene(count: count)

            let cgCtx = context()
            cg.render(scene, in: cgCtx, viewport: viewport, size: size) // warm
            let cgMs = milliseconds(5) { cg.render(scene, in: cgCtx, viewport: viewport, size: size) }

            let metalCtx = context()
            metal.render(scene, in: metalCtx, viewport: viewport, size: size) // warm
            let metalMs = milliseconds(5) { metal.render(scene, in: metalCtx, viewport: viewport, size: size) }

            // GPU-only frame (no read-back, no overlay).
            metal.renderDirectFrame(
                scene: scene, viewport: viewport, size: size, theme: .light, pixelWidth: width, pixelHeight: height
            )
            let directMs = milliseconds(5) {
                metal.renderDirectFrame(
                    scene: scene, viewport: viewport, size: size, theme: .light,
                    pixelWidth: width, pixelHeight: height
                )
            }

            // Editor hybrid: GPU direct frame + the CG text/selection overlay
            // (everything the GPU doesn't handle — i.e. text).
            let overlayCtx = context()
            let hybridMs = milliseconds(5) {
                metal.renderDirectFrame(
                    scene: scene, viewport: viewport, size: size, theme: .light,
                    pixelWidth: width, pixelHeight: height
                )
                cg.render(
                    scene, in: overlayCtx, viewport: viewport, size: size,
                    theme: .light, skipping: gpuHandled, fillBackground: false
                )
            }

            XCTAssertGreaterThan(inkFraction(cgCtx), 0.01, "all-types n=\(count): CG drew nothing")
            XCTAssertGreaterThan(inkFraction(metalCtx), 0.01, "all-types n=\(count): Metal drew nothing")
            print(String(
                format: "ALL-TYPES BENCH n=%4d  cpu=%6.1f ms  metal=%6.1f ms (%.2fx)  "
                    + "direct=%5.1f ms (%.2fx)  hybrid=%5.1f ms (%.2fx)",
                count, cgMs, metalMs, cgMs / metalMs, directMs, cgMs / directMs, hybridMs, cgMs / hybridMs
            ))
        }
    }
}
