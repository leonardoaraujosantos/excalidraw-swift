import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import ExcalidrawRender

/// Layered canvas rendering (Phase 7.5 Stage B): during an interaction the
/// committed scene is cached as a static-layer image and only the in-flight
/// elements + overlay are redrawn per frame; idle frames render the whole scene.
public extension EditorModel {
    /// Capture which elements are "dynamic" for this interaction — the moved/
    /// created element plus its bound arrows/text and any frame children — so
    /// everything else can be cached as the static layer.
    func beginDynamicLayer() {
        var ids = controller.selectedIDs
        for element in controller.selectedElements {
            ids.formUnion(element.base.boundElements?.map(\.id) ?? [])
            if Frames.isFrame(element) {
                ids.formUnion(Frames.children(ofFrame: element.id, in: controller.scene.visibleElements).map(\.id))
            }
        }
        dynamicIDs = ids
        staticToken &+= 1
        staticLayer.invalidate()
    }

    func endDynamicLayer() {
        dynamicIDs = []
        staticLayer.invalidate()
    }

    /// The cached static-layer image (everything except `dynamicIDs`) for the
    /// current interaction, or `nil` when idle (caller does a full render).
    func staticLayerImage(size: CGSize) -> CGImage? {
        guard !dynamicIDs.isEmpty, size.width > 0, size.height > 0 else { return nil }
        return staticLayer.image(token: staticToken) {
            renderOffscreen(skipping: dynamicIDs, size: size)
        }
    }

    /// Full-scene render + overlay (idle frames).
    func renderFull(into ctx: CGContext, size: CGSize) {
        renderer.render(controller.scene, in: ctx, viewport: viewport, size: size, theme: theme)
        drawOverlay(into: ctx, size: size)
    }

    /// Dynamic-only render (over the blitted static image) + overlay.
    func renderDynamicOverlay(into ctx: CGContext, size: CGSize) {
        let staticIDs = Set(controller.scene.visibleElements.map(\.id)).subtracting(dynamicIDs)
        renderer.render(
            controller.scene, in: ctx, viewport: viewport, size: size,
            theme: theme, skipping: staticIDs, fillBackground: false
        )
        drawOverlay(into: ctx, size: size)
    }

    /// Draw the interactive overlay (selection box, handles, snap lines, linear
    /// and crop edit handles) into `ctx`.
    func drawOverlay(into ctx: CGContext, size: CGSize) {
        let handles = controller.transformHandles()
        InteractiveRenderer.render(
            selectionBounds: controller.selectionBounds,
            handles: handles.filter { $0.key != .rotation }.map(\.value),
            rotationHandle: handles[.rotation],
            selectionRect: controller.selectionRect,
            in: ctx, viewport: viewport, size: size,
            snapLinesX: controller.snapLinesX,
            snapLinesY: controller.snapLinesY,
            linearPoints: linearOverlay.points,
            linearMidpoints: linearOverlay.midpoints,
            cropFrame: cropOverlay?.frame,
            cropHandles: cropOverlay?.handles ?? []
        )
    }

    private func renderOffscreen(skipping: Set<String>, size: CGSize) -> CGImage? {
        let w = Int(size.width * displayScale), h = Int(size.height * displayScale)
        guard w > 0, h > 0, let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: displayScale, y: displayScale)
        renderer.render(controller.scene, in: ctx, viewport: viewport, size: size, theme: theme, skipping: skipping)
        return ctx.makeImage()
    }
}
