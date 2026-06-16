import CoreGraphics
import CoreText
import ExcalidrawModel
import Foundation

/// Draws text elements with Core Text. Lines are split on `\n` and laid out at
/// `fontSize * lineHeight` spacing, assuming a y-down context (SwiftUI `Canvas`
/// / UIKit). Font-family mapping to the bundled Excalidraw fonts and exact
/// metric parity are Phase 4 work; this uses a system fallback font.
public enum TextLayout {
    public static func draw(
        _ text: TextProperties, base _: BaseProperties, in ctx: CGContext, color: CGColor
    ) {
        let font = CTFontCreateWithName(fontName(for: text.fontFamily) as CFString, text.fontSize, nil)
        let ascent = CTFontGetAscent(font)
        let lineHeightPx = text.fontSize * text.lineHeight
        let lines = text.text.components(separatedBy: "\n")

        for (index, lineText) in lines.enumerated() where !lineText.isEmpty {
            // Use Core Text attribute keys so this compiles without UIKit/AppKit.
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
            let attributed = NSAttributedString(string: lineText, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attributed)

            let baseline = lineHeightPx * Double(index) + ascent
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: baseline)
            ctx.scaleBy(x: 1, y: -1) // flip so Core Text draws upright in a y-down context
            ctx.textPosition = .zero
            CTLineDraw(ctLine, ctx)
            ctx.restoreGState()
        }
    }

    /// Measure the rendered size of a text block (widest line × total height).
    public static func measure(_ text: TextProperties) -> CGSize {
        let font = CTFontCreateWithName(fontName(for: text.fontFamily) as CFString, text.fontSize, nil)
        let lines = text.text.components(separatedBy: "\n")
        var maxWidth = 0.0
        for lineText in lines where !lineText.isEmpty {
            let attributed = NSAttributedString(
                string: lineText,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            maxWidth = max(
                maxWidth,
                CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
            )
        }
        let height = Double(max(lines.count, 1)) * text.fontSize * text.lineHeight
        return CGSize(width: maxWidth, height: height)
    }

    /// Map an Excalidraw font-family id to the closest system font. The
    /// hand-drawn families (Excalifont/Virgil/Nunito/etc.) map to a handwriting
    /// system font for an Excalidraw-like feel; bundling the actual fonts with
    /// matching metrics is a later refinement.
    static func fontName(for family: Int) -> String {
        switch family {
        case FontFamily.helvetica, FontFamily.liberationSans, FontFamily.assistant: "Helvetica"
        case FontFamily.cascadia, FontFamily.comicShanns: "Menlo"
        default: "Bradley Hand" // Excalifont / Virgil / Nunito / LilitaOne → handwriting
        }
    }
}
