import CoreGraphics
import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawRender

final class SceneRenderTests: XCTestCase {
    private func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    private func rgb(_ ctx: CGContext, width: Int, height: Int) -> (UnsafeMutablePointer<UInt8>, Int) {
        (ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4), width * height * 4)
    }

    private func base(_ id: String, x: Double, y: Double, w: Double = 50, h: Double = 30) -> BaseProperties {
        var b = BaseProperties(id: id)
        b.x = x; b.y = y; b.width = w; b.height = h; b.seed = 1
        return b
    }

    func testRendersNonBlankScene() {
        var rect = base("r", x: 20, y: 20, w: 100, h: 60); rect.backgroundColor = "#ff0000"
        var ell = base("e", x: 200, y: 20, w: 100, h: 60); ell.strokeColor = "#1971c2"
        let text = base("t", x: 40, y: 150)
        let scene = Scene(elements: [
            ExcalidrawElement(base: rect, kind: .rectangle),
            ExcalidrawElement(base: ell, kind: .ellipse),
            ExcalidrawElement(base: text, kind: .text(TextProperties(text: "Hello", originalText: "Hello")))
        ])

        let (w, h) = (400, 240)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))

        let (px, total) = rgb(ctx, width: w, height: h)
        var inked = 0
        for i in stride(from: 0, to: total, by: 4) where !(px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255) {
            inked += 1
        }
        XCTAssertGreaterThan(inked, 200, "expected the scene to ink many pixels")
    }

    func testEmbeddableRendersPlaceholder() {
        var emb = base("emb", x: 20, y: 20, w: 100, h: 80)
        emb.strokeColor = "#1e1e1e"
        let scene = Scene(elements: [ExcalidrawElement(base: emb, kind: .embeddable)])
        let (w, h) = (140, 120)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))

        let (px, total) = rgb(ctx, width: w, height: h)
        var inked = 0
        for i in stride(from: 0, to: total, by: 4) where !(px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255) {
            inked += 1
        }
        XCTAssertGreaterThan(inked, 200, "embeddable should render a visible placeholder")
    }

    func testOffScreenElementIsCulled() {
        // A far-away element must not ink the viewport.
        var far = base("far", x: 100_000, y: 100_000, w: 100, h: 80); far.backgroundColor = "#ff0000"
        far.fillStyle = .solid
        let scene = Scene(elements: [ExcalidrawElement(base: far, kind: .rectangle)])
        let (w, h) = (200, 160)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))

        let (px, total) = rgb(ctx, width: w, height: h)
        var inked = 0
        for i in stride(from: 0, to: total, by: 4) where !(px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255) {
            inked += 1
        }
        XCTAssertEqual(inked, 0, "off-screen element should be culled")
    }

    func testSolidFillProducesFillColoredPixels() {
        var rect = base("r", x: 10, y: 10, w: 100, h: 80)
        rect.backgroundColor = "#ff0000"
        rect.fillStyle = .solid
        let scene = Scene(elements: [ExcalidrawElement(base: rect, kind: .rectangle)])

        let (w, h) = (140, 120)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))

        let (px, total) = rgb(ctx, width: w, height: h)
        var redPixels = 0
        for i in stride(from: 0, to: total, by: 4) where px[i] > 200 && px[i + 1] < 100 && px[i + 2] < 100 {
            redPixels += 1
        }
        XCTAssertGreaterThan(redPixels, 100, "solid fill should produce red interior pixels")
    }

    func testBackgroundColorFills() {
        var s = Scene()
        s.appState = AppState(raw: ["viewBackgroundColor": .string("#00ff00")])
        let (w, h) = (20, 20)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(s, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))
        let (px, _) = rgb(ctx, width: w, height: h)
        XCTAssertGreaterThan(px[1], 200) // green channel of first pixel
        XCTAssertLessThan(px[0], 100)
    }

    func testGridRendersWithoutElements() {
        var s = Scene()
        s.appState = AppState(raw: ["gridModeEnabled": .bool(true)])
        let (w, h) = (100, 100)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(s, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))
        let (px, total) = rgb(ctx, width: w, height: h)
        var nonWhite = 0
        for i in stride(from: 0, to: total, by: 4) where px[i] < 255 {
            nonWhite += 1
        }
        XCTAssertGreaterThan(nonWhite, 0, "grid lines should be drawn")
    }

    private func inkedCount(_ ctx: CGContext, width: Int, height: Int) -> Int {
        let (px, total) = rgb(ctx, width: width, height: height)
        var inked = 0
        for i in stride(from: 0, to: total, by: 4) where !(px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255) {
            inked += 1
        }
        return inked
    }

    func testRendersFreedrawAndRotatedDashedShapes() {
        var free = base("f", x: 20, y: 20, w: 60, h: 40); free.strokeColor = "#1971c2"
        let freeProps = FreedrawProperties(points: [Point(0, 0), Point(30, 20), Point(60, 0), Point(40, 40)])
        var dashed = base("d", x: 100, y: 20, w: 80, h: 60)
        dashed.strokeStyle = .dashed
        dashed.angle = .pi / 6 // exercises the rotation branch
        let scene = Scene(elements: [
            ExcalidrawElement(base: free, kind: .freedraw(freeProps)),
            ExcalidrawElement(base: dashed, kind: .rectangle)
        ])
        let (w, h) = (220, 120)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))
        XCTAssertGreaterThan(inkedCount(ctx, width: w, height: h), 50)
    }

    func testRendersImageElement() {
        let payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let file = BinaryFileData(
            mimeType: "image/png", id: "img", dataURL: "data:image/png;base64,\(payload)", created: 0
        )
        var img = base("i", x: 10, y: 10, w: 50, h: 50)
        img.backgroundColor = "transparent"
        let scene = Scene(
            elements: [ExcalidrawElement(base: img, kind: .image(ImageProperties(fileId: "img", status: .saved)))],
            files: ["img": file]
        )
        let (w, h) = (80, 80)
        let ctx = context(width: w, height: h)
        // Exercises the image-draw branch; the decoder must produce an image and
        // rendering must complete without crashing.
        XCTAssertNotNil(ImageDecoder().image(fileId: "img", dataURL: file.dataURL))
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))
    }

    func testRendersArrowWithHead() {
        let b = base("a", x: 10, y: 10, w: 100, h: 0)
        let arrow = ArrowProperties(points: [Point(0, 0), Point(100, 0)], endArrowhead: .triangle)
        let scene = Scene(elements: [ExcalidrawElement(base: b, kind: .arrow(arrow))])
        _ = b
        let (w, h) = (140, 60)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))
        XCTAssertGreaterThan(inkedCount(ctx, width: w, height: h), 40)
    }

    func testRendersFreedrawFilledStroke() {
        var b = base("f", x: 10, y: 10, w: 80, h: 40); b.strokeColor = "#1971c2"
        let free = FreedrawProperties(
            points: [Point(0, 0), Point(20, 20), Point(40, 0), Point(60, 30), Point(80, 10)],
            pressures: [0.5, 0.7, 0.6, 0.8, 0.5], simulatePressure: false
        )
        let scene = Scene(elements: [ExcalidrawElement(base: b, kind: .freedraw(free))])
        let (w, h) = (120, 80)
        let ctx = context(width: w, height: h)
        SceneRenderer().render(scene, in: ctx, viewport: Viewport(), size: CGSize(width: w, height: h))
        XCTAssertGreaterThan(inkedCount(ctx, width: w, height: h), 40)
    }

    func testReusedRendererReflectsResizeWithoutVersionBump() {
        // Regression for the "empty rectangle while drawing" bug: the same
        // renderer must redraw a shape after its size grows via replace().
        let renderer = SceneRenderer()
        var rect = base("r", x: 10, y: 10, w: 1, h: 1)
        rect.backgroundColor = "#ff0000"
        rect.fillStyle = .solid
        var scene = Scene(elements: [ExcalidrawElement(base: rect, kind: .rectangle)])

        let (w, h) = (160, 120)
        let ctx1 = context(width: w, height: h)
        renderer.render(scene, in: ctx1, viewport: Viewport(), size: CGSize(width: w, height: h))
        let tiny = inkedCount(ctx1, width: w, height: h)

        // Grow it (no version bump), render again with the SAME renderer.
        rect.width = 120
        rect.height = 80
        scene.replace(ExcalidrawElement(base: rect, kind: .rectangle))
        let ctx2 = context(width: w, height: h)
        renderer.render(scene, in: ctx2, viewport: Viewport(), size: CGSize(width: w, height: h))
        let grown = inkedCount(ctx2, width: w, height: h)

        XCTAssertGreaterThan(grown, tiny + 500)
    }

    func testColorParser() throws {
        let red = try XCTUnwrap(ColorParser.cgColor("#ff0000"))
        XCTAssertEqual(red.components?[0], 1)
        XCTAssertEqual(red.components?[1], 0)
        let short = try XCTUnwrap(ColorParser.cgColor("#fff"))
        XCTAssertEqual(short.components?[0], 1)
        let alpha = try XCTUnwrap(ColorParser.cgColor("#ff000080"))
        XCTAssertEqual(alpha.alpha, CGFloat(128) / 255, accuracy: 0.01)
        XCTAssertEqual(ColorParser.cgColor("transparent")?.alpha, 0)
        XCTAssertTrue(ColorParser.isTransparent("#ff000000"))
    }

    func testImageDecoder() {
        let payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let dataURL = "data:image/png;base64,\(payload)"
        let decoder = ImageDecoder()
        let image = decoder.image(fileId: "f1", dataURL: dataURL)
        XCTAssertNotNil(image)
        XCTAssertNotNil(decoder.image(fileId: "f1", dataURL: dataURL)) // cached path
        XCTAssertNil(ImageDecoder.decode(dataURL: "not-a-data-url"))
    }
}
