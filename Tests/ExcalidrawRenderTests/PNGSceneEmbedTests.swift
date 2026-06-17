import CoreGraphics
import ExcalidrawMath
import ExcalidrawModel
import ImageIO
import XCTest
@testable import ExcalidrawRender

final class PNGSceneEmbedTests: XCTestCase {
    private func scene() -> Scene {
        var rect = BaseProperties(id: "r"); rect.x = 10; rect.y = 20; rect.width = 100; rect.height = 60
        rect.backgroundColor = "#a5d8ff"
        var text = BaseProperties(id: "t"); text.x = 30; text.y = 30; text.width = 80; text.height = 24
        return Scene(elements: [
            ExcalidrawElement(base: rect, kind: .rectangle),
            ExcalidrawElement(base: text, kind: .text(TextProperties(text: "héllo • ünïcode")))
        ])
    }

    func testExportedPNGEmbedsAndReopensScene() throws {
        let original = scene()
        let png = try XCTUnwrap(Exporter.pngData(original))
        XCTAssertTrue(PNGSceneEmbed.containsScene(png))

        let restored = try XCTUnwrap(PNGSceneEmbed.extractScene(from: png))
        XCTAssertEqual(restored.visibleElements.count, original.visibleElements.count)
        XCTAssertEqual(restored.element(id: "r")?.base.backgroundColor, "#a5d8ff")
        if case let .text(props)? = restored.element(id: "t")?.kind {
            XCTAssertEqual(props.text, "héllo • ünïcode") // UTF-8 survives
        } else {
            XCTFail("text element missing after round-trip")
        }
    }

    func testExportWithoutEmbedHasNoScene() throws {
        let png = try XCTUnwrap(Exporter.pngData(scene(), embedScene: false))
        XCTAssertFalse(PNGSceneEmbed.containsScene(png))
        XCTAssertNil(PNGSceneEmbed.extractScene(from: png))
    }

    func testEmbeddedPNGIsStillAValidImage() throws {
        // The chunk must be inserted without corrupting the PNG (CRC etc.), so it
        // still decodes as an image.
        let png = try XCTUnwrap(Exporter.pngData(scene()))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testExtractFromNonPNGOrPlainPNGReturnsNil() {
        XCTAssertNil(PNGSceneEmbed.extractScene(from: Data([1, 2, 3, 4])))
        XCTAssertFalse(PNGSceneEmbed.containsScene(Data()))
    }
}
