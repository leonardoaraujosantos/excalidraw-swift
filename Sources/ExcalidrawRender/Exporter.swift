import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawModel
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Exports a scene to a PNG, fitting the content with padding at a given scale.
/// Ports the intent of `packages/utils/src/export.ts` (canvas export).
public enum Exporter {
    public struct Options {
        public var scale: Double
        public var padding: Double
        public init(scale: Double = 2, padding: Double = 16) {
            self.scale = scale
            self.padding = padding
        }
    }

    /// Render the scene's visible content to a PNG. Returns `nil` for an empty
    /// scene or on failure. When `embedScene` is true the scene JSON is embedded
    /// in the PNG so the image can be re-opened as an editable drawing.
    public static func pngData(
        _ scene: Scene, options: Options = Options(), embedScene: Bool = true
    ) -> Data? {
        guard let image = cgImage(scene, options: options) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let png = data as Data
        return embedScene ? (PNGSceneEmbed.embed(scene, into: png) ?? png) : png
    }

    public static func cgImage(_ scene: Scene, options: Options = Options()) -> CGImage? {
        guard let bounds = ElementGeometry.commonBounds(scene.visibleElements) else { return nil }
        let scale = options.scale
        let padding = options.padding
        let sceneWidth = bounds.width + 2 * padding
        let sceneHeight = bounds.height + 2 * padding
        let pixelWidth = Int((sceneWidth * scale).rounded(.up))
        let pixelHeight = Int((sceneHeight * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip to a y-down coordinate system so the scene renders upright.
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: 1, y: -1)

        let viewport = Viewport(
            scrollX: padding - bounds.minX,
            scrollY: padding - bounds.minY,
            zoom: scale
        )
        SceneRenderer().render(
            scene,
            in: ctx,
            viewport: viewport,
            size: CGSize(width: pixelWidth, height: pixelHeight)
        )
        return ctx.makeImage()
    }
}
