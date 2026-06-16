import CoreGraphics
import ExcalidrawMath
import ExcalidrawModel
import ExcalidrawRender
import XCTest
@testable import ExcalidrawMetal

/// Exercises the geometry builder (host-independent) and, when a Metal device is
/// present, the full GPU render path with off-screen readback compared against
/// the Core Graphics renderer.
final class MetalSceneRendererTests: XCTestCase {
    private let size = CGSize(width: 200, height: 160)

    private func base(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> BaseProperties {
        var b = BaseProperties(id: id); b.x = x; b.y = y; b.width = w; b.height = h; b.seed = 7
        b.strokeColor = "#1e1e1e"
        return b
    }

    private func shapesScene() -> Scene {
        var rect = base("r", 16, 20, 120, 60); rect.backgroundColor = "#ffc9c9"; rect.fillStyle = .solid
        let ell = base("e", 40, 90, 100, 50)
        return Scene(elements: [
            ExcalidrawElement(base: rect, kind: .rectangle),
            ExcalidrawElement(base: ell, kind: .ellipse)
        ])
    }

    // MARK: Geometry (no GPU required)

    func testGeometryHandlesRoughShapesAndSkipsText() {
        var textBase = base("t", 10, 10, 80, 24)
        textBase.strokeColor = "#000000"
        var scene = shapesScene()
        scene = Scene(elements: scene.visibleElements + [
            ExcalidrawElement(base: textBase, kind: .text(TextProperties(text: "hi")))
        ])
        let geometry = SceneGeometry(scene: scene, theme: .light)
        XCTAssertTrue(geometry.handledIDs.contains("r"))
        XCTAssertTrue(geometry.handledIDs.contains("e"))
        XCTAssertFalse(geometry.handledIDs.contains("t"), "text must fall through to the CG overlay")
        XCTAssertFalse(geometry.isEmpty)
        XCTAssertEqual(geometry.vertices.count % 9, 0) // 3 floats/vertex × 3 vertices
    }

    func testGeometrySkipsFramedAndDashedElements() {
        var dashed = base("d", 10, 10, 80, 40); dashed.strokeStyle = .dashed
        var framed = base("f", 10, 60, 80, 40); framed.frameId = "frame-1"
        let scene = Scene(elements: [
            ExcalidrawElement(base: dashed, kind: .rectangle),
            ExcalidrawElement(base: framed, kind: .rectangle)
        ])
        let geometry = SceneGeometry(scene: scene, theme: .light)
        XCTAssertTrue(geometry.handledIDs.isEmpty, "dashed + framed elements stay with Core Graphics")
        XCTAssertTrue(geometry.isEmpty)
    }

    func testGeometryRespectsSkippingSet() {
        let scene = shapesScene()
        let geometry = SceneGeometry(scene: scene, theme: .light, skipping: ["r"])
        XCTAssertFalse(geometry.handledIDs.contains("r"))
        XCTAssertTrue(geometry.handledIDs.contains("e"))
    }

    func testClipTransformMapsSceneToClipSpace() {
        let viewport = Viewport(scrollX: 0, scrollY: 0, zoom: 1)
        let t = MetalSceneRenderer.clipTransform(viewport: viewport, size: size)
        // Scene origin maps to the top-left clip corner (-1, +1); the far corner
        // maps to (+1, -1).
        XCTAssertEqual(t.ax * 0 + t.bx, -1, accuracy: 1e-5)
        XCTAssertEqual(t.cy * 0 + t.dy, 1, accuracy: 1e-5)
        XCTAssertEqual(t.ax * Float(size.width) + t.bx, 1, accuracy: 1e-5)
        XCTAssertEqual(t.cy * Float(size.height) + t.dy, -1, accuracy: 1e-5)
    }

    // MARK: GPU path (skips when no Metal device, e.g. headless CI)

    func testMetalRendererProducesNonEmptyImageMatchingCG() throws {
        guard let metal = MetalSceneRenderer() else {
            throw XCTSkip("No Metal device on this host")
        }
        let scene = shapesScene()
        let viewport = Viewport()

        let metalPixels = render(scene, viewport: viewport, with: metal)
        let cgPixels = render(scene, viewport: viewport, with: SceneRenderer())

        // The GPU pass must actually draw something dark over the white bg.
        let metalInk = inkFraction(metalPixels)
        XCTAssertGreaterThan(metalInk, 0.02, "Metal render should contain shape pixels")

        // And it should broadly agree with the CG renderer (rough.js seeds and
        // antialiasing differ, so this is a coarse structural check).
        let cgInk = inkFraction(cgPixels)
        XCTAssertEqual(metalInk, cgInk, accuracy: 0.12)
    }

    func testMetalAndCGAgreeOnBackgroundCorners() throws {
        guard let metal = MetalSceneRenderer() else {
            throw XCTSkip("No Metal device on this host")
        }
        let scene = shapesScene()
        let pixels = render(scene, viewport: Viewport(), with: metal)
        // Top-left corner is empty canvas → white background from the GPU clear.
        let (r, g, b) = pixel(pixels, x: 2, y: 2)
        XCTAssertGreaterThan(r, 230); XCTAssertGreaterThan(g, 230); XCTAssertGreaterThan(b, 230)
    }

    func testMetalPaintsBackgroundWithNoTessellatedShapes() throws {
        guard let metal = MetalSceneRenderer() else {
            throw XCTSkip("No Metal device on this host")
        }
        // Only a text element → no GPU geometry. The GPU clear must still paint
        // the white background (regression for the empty-geometry path).
        var textBase = BaseProperties(id: "t"); textBase.x = 10; textBase.y = 10
        textBase.width = 80; textBase.height = 24; textBase.strokeColor = "#000000"
        let scene = Scene(elements: [ExcalidrawElement(base: textBase, kind: .text(TextProperties(text: "hi")))])
        let pixels = render(scene, viewport: Viewport(), with: metal)
        let (r, g, b) = pixel(pixels, x: 180, y: 150) // a corner away from the text
        XCTAssertGreaterThan(r, 230); XCTAssertGreaterThan(g, 230); XCTAssertGreaterThan(b, 230)
    }

    func testRenderTimedReportsPhasesAndCacheSpeedsUpSecondFrame() throws {
        guard let metal = MetalSceneRenderer() else {
            throw XCTSkip("No Metal device on this host")
        }
        let scene = shapesScene()
        let viewport = Viewport()
        func ctx() -> CGContext {
            CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
        }
        // First frame fills the geometry cache; second frame must reuse it, so
        // its geometry phase is no slower (caches live on the renderer).
        let cold = metal.renderTimed(scene, in: ctx(), viewport: viewport, size: size)
        let warm = metal.renderTimed(scene, in: ctx(), viewport: viewport, size: size)
        XCTAssertGreaterThan(cold.gpuMs, 0)
        XCTAssertLessThanOrEqual(warm.geometryMs, cold.geometryMs + 1.0)
    }

    // MARK: Helpers

    private func render(_ scene: Scene, viewport: Viewport, with renderer: SceneRendering) -> [UInt8] {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        renderer.render(scene, in: ctx, viewport: viewport, size: size, theme: .light)
        let data = ctx.data!
        return [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
    }

    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let w = Int(size.width)
        let i = (y * w + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

    /// Fraction of pixels noticeably darker than white (i.e. drawn shape ink).
    private func inkFraction(_ pixels: [UInt8]) -> Double {
        var ink = 0
        let count = pixels.count / 4
        for i in 0 ..< count {
            let r = pixels[i * 4], g = pixels[i * 4 + 1], b = pixels[i * 4 + 2]
            if Int(r) + Int(g) + Int(b) < 600 { ink += 1 }
        }
        return Double(ink) / Double(count)
    }
}
