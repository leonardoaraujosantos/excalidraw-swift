import CoreGraphics
import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawRender

/// Stage-A rendering benchmarks (Phase 7.5). These print steady-state
/// `SceneRenderer.render` timings for synthetic heavy scenes so we can see
/// where time goes before accelerating. They assert *correctness* (the scene
/// inks pixels), never wall-clock thresholds, so they don't flake in CI — read
/// the printed `BENCH` lines for the numbers.
final class RenderBenchmarkTests: XCTestCase {
    private func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// A deterministic grid of mixed elements with fills and a few dense
    /// freedraw strokes — a stand-in for a busy board.
    private func syntheticScene(count: Int) -> Scene {
        let perRow = Int(Double(count).squareRoot().rounded(.up))
        let cell = 90.0
        var elements: [ExcalidrawElement] = []
        for i in 0 ..< count {
            let col = i % perRow, row = i / perRow
            var b = BaseProperties(id: "e\(i)")
            b.x = Double(col) * cell + 10
            b.y = Double(row) * cell + 10
            b.width = 70; b.height = 60
            b.seed = i + 1
            b.strokeColor = "#1e1e1e"
            switch i % 5 {
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
                    base: b,
                    kind: .arrow(ArrowProperties(points: pts, endArrowhead: .arrow))
                ))
            default:
                // A dense freedraw stroke (many points) to stress path rasterization.
                let pts = (0 ..< 200).map { j in Point(Double(j % 70), Double((j * 7) % 60)) }
                elements.append(ExcalidrawElement(base: b, kind: .freedraw(FreedrawProperties(points: pts))))
            }
        }
        return Scene(elements: elements)
    }

    private func inked(_ ctx: CGContext, _ w: Int, _ h: Int) -> Int {
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var count = 0
        for i in stride(from: 0, to: w * h * 4, by: 4) where !(px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255) {
            count += 1
        }
        return count
    }

    func testRenderTimingScalesWithSceneSize() {
        let (w, h) = (1200, 800)
        let size = CGSize(width: w, height: h)
        for count in [100, 500, 1500] {
            let scene = syntheticScene(count: count)
            let renderer = SceneRenderer()
            let ctx = context(width: w, height: h)
            renderer.render(scene, in: ctx, viewport: Viewport(), size: size) // warm ShapeCache

            let iterations = 5
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0 ..< iterations {
                renderer.render(scene, in: ctx, viewport: Viewport(), size: size)
            }
            let msPerFrame = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
            print(String(format: "BENCH render full-scene n=%4d: %.2f ms/frame", count, msPerFrame))
            XCTAssertGreaterThan(inked(ctx, w, h), 0)
        }
    }

    private func blit(_ image: CGImage, into ctx: CGContext, _ w: Int, _ h: Int) {
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func testLayeredFrameIsCheaperThanFullRepaint() throws {
        // Stage B: while dragging one element, a frame should be a cached-static
        // blit + a single-element redraw — far cheaper than repainting all 1500.
        let (w, h) = (1200, 800)
        let size = CGSize(width: w, height: h)
        let scene = syntheticScene(count: 1500)
        let renderer = SceneRenderer()
        let viewport = Viewport()
        let allIDs = Set(scene.visibleElements.map(\.id))
        let dynamic: Set = ["e0"] // pretend e0 is being dragged

        // Baseline: full repaint per frame.
        let fullCtx = context(width: w, height: h)
        renderer.render(scene, in: fullCtx, viewport: viewport, size: size)
        var start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< 10 {
            renderer.render(scene, in: fullCtx, viewport: viewport, size: size)
        }
        let fullMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / 10

        // Stage B: build the static layer once, then per frame blit + redraw e0.
        let staticCtx = context(width: w, height: h)
        renderer.render(scene, in: staticCtx, viewport: viewport, size: size, skipping: dynamic)
        let staticImage = try XCTUnwrap(staticCtx.makeImage())
        let frameCtx = context(width: w, height: h)
        start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< 10 {
            blit(staticImage, into: frameCtx, w, h)
            renderer.render(
                scene, in: frameCtx, viewport: viewport, size: size,
                skipping: allIDs.subtracting(dynamic), fillBackground: false
            )
        }
        let layeredMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / 10

        print(String(format: "BENCH full repaint n=1500: %.2f ms/frame", fullMs))
        print(String(
            format: "BENCH layered frame  n=1500: %.2f ms/frame (%.1fx faster)",
            layeredMs,
            fullMs / layeredMs
        ))
        XCTAssertLessThan(layeredMs, fullMs, "layered frame should be cheaper than a full repaint")
    }

    func testCullingReducesWorkWhenZoomedIn() {
        // Same scene, but a zoomed-in viewport showing a small corner: culling
        // should make a frame much cheaper than the full-scene render.
        let (w, h) = (1200, 800)
        let size = CGSize(width: w, height: h)
        let scene = syntheticScene(count: 1500)
        let renderer = SceneRenderer()
        let zoomed = Viewport(scrollX: 0, scrollY: 0, zoom: 4)

        renderer.render(scene, in: context(width: w, height: h), viewport: zoomed, size: size)
        let ctx = context(width: w, height: h)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< 5 {
            renderer.render(scene, in: ctx, viewport: zoomed, size: size)
        }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / 5
        print(String(format: "BENCH render zoomed(4x, culled) n=1500: %.2f ms/frame", ms))
    }
}
