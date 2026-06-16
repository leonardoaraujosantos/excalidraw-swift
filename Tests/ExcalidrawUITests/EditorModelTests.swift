import CoreGraphics
import ExcalidrawEditor
import ExcalidrawMath
import ExcalidrawModel
import ExcalidrawRender
import XCTest
@testable import ExcalidrawUI

@MainActor
final class EditorModelTests: XCTestCase {
    private func draw(_ m: EditorModel, from: CGPoint, to: CGPoint) {
        m.pointer(.down, at: from)
        m.pointer(.move, at: to)
        m.pointer(.up, at: to)
    }

    func testForwardsPointerAndCreatesElement() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        let before = m.revision
        draw(m, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
        XCTAssertEqual(m.controller.scene.visibleElements.count, 1)
        XCTAssertGreaterThan(m.revision, before)
        XCTAssertEqual(m.activeTool, .selection) // reverts after creation
    }

    func testViewToSceneConversionWithViewport() {
        let m = EditorModel(viewport: Viewport(scrollX: 0, scrollY: 0, zoom: 2))
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))
        // View (20,20) at zoom 2 → scene (10,10).
        XCTAssertEqual(m.controller.scene.visibleElements.first?.base.x, 10)
    }

    func testFontControlsApplyToSelectedText() {
        let m = EditorModel()
        m.select(tool: .text)
        m.pointer(.down, at: CGPoint(x: 20, y: 20))
        m.editingText = "Hi"
        m.commitText()
        m.controller.selectAll()
        m.setFontSize(36)
        m.setFontFamily(FontFamily.cascadia)
        guard case let .text(props) = m.controller.scene.visibleElements.first?.kind else { return XCTFail("text") }
        XCTAssertEqual(props.fontSize, 36)
        XCTAssertEqual(props.fontFamily, FontFamily.cascadia)
        XCTAssertEqual(m.fontSize, 36)
    }

    func testStrokeColorAndWidthApplyToSelection() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        m.setStrokeColor("#e03131")
        m.setStrokeWidth(6)
        let element = m.controller.selectedElements.first
        XCTAssertEqual(element?.base.strokeColor, "#e03131")
        XCTAssertEqual(element?.base.strokeWidth, 6)
        XCTAssertEqual(m.controller.currentItem.strokeColor, "#e03131")
    }

    func testUndoRedoDelete() {
        let m = EditorModel()
        m.select(tool: .ellipse)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40))
        m.undo()
        XCTAssertEqual(m.controller.scene.visibleElements.count, 0)
        m.redo()
        XCTAssertEqual(m.controller.scene.visibleElements.count, 1)
        m.controller.selectAll()
        m.deleteSelected()
        XCTAssertEqual(m.controller.scene.visibleElements.count, 0)
    }

    func testPanZoomUpdatesViewport() {
        let m = EditorModel(viewport: Viewport(scrollX: 0, scrollY: 0, zoom: 1))
        m.panZoom(translation: CGSize(width: 10, height: 20), scale: 2)
        XCTAssertEqual(m.viewport.zoom, 2)
        XCTAssertEqual(m.controller.zoom, 2)
        XCTAssertEqual(m.viewport.scrollX, 5) // 10 / zoom(2)
    }

    func testPropertySettersApplyToSelection() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        m.setBackgroundColor("#a5d8ff")
        m.setFillStyle(.crossHatch)
        m.setStrokeStyle(.dashed)
        m.setOpacity(60)
        let e = m.controller.selectedElements.first
        XCTAssertEqual(e?.base.backgroundColor, "#a5d8ff")
        XCTAssertEqual(e?.base.fillStyle, .crossHatch)
        XCTAssertEqual(e?.base.strokeStyle, .dashed)
        XCTAssertEqual(e?.base.opacity, 60)
    }

    func testActionPassthroughs() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40))
        m.controller.selectAll()
        m.duplicate()
        XCTAssertEqual(m.controller.scene.visibleElements.count, 2)
        m.controller.selectAll()
        m.bringToFront() // should not crash
        m.sendToBack()
    }

    func testTextToolCreatesAndCommits() {
        let m = EditorModel()
        m.select(tool: .text)
        m.pointer(.down, at: CGPoint(x: 10, y: 10))
        XCTAssertNotNil(m.editingTextID)
        m.editingText = "Hello"
        m.commitText()
        XCTAssertNil(m.editingTextID)
        XCTAssertEqual(m.activeTool, .selection)
        guard case let .text(props) = m.controller.scene.visibleElements.first?.kind else { return XCTFail("text") }
        XCTAssertEqual(props.text, "Hello")
    }

    func testEmptyTextCommitAddsNothing() {
        let m = EditorModel()
        m.select(tool: .text)
        m.pointer(.down, at: CGPoint(x: 10, y: 10))
        m.editingText = "   "
        m.commitText()
        XCTAssertTrue(m.controller.scene.visibleElements.isEmpty)
    }

    func testInsertImage() throws {
        let payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let m = EditorModel()
        m.insertImage(data: data, mimeType: "image/png", viewSize: CGSize(width: 400, height: 400))
        XCTAssertEqual(m.controller.scene.visibleElements.count, 1)
        guard case .image = m.controller.scene.visibleElements.first?.kind else { return XCTFail("image") }
        XCTAssertEqual(m.controller.scene.files.count, 1)
    }

    func testDoubleTapImageEntersCropOverlay() throws {
        // 1×1 PNG.
        let payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let m = EditorModel()
        m.insertImage(data: data, mimeType: "image/png", viewSize: CGSize(width: 400, height: 400))
        let image = try XCTUnwrap(m.controller.scene.visibleElements.first)
        // Double-tap the image centre (scene == view at identity viewport).
        let center = CGPoint(x: image.base.x + image.base.width / 2, y: image.base.y + image.base.height / 2)
        m.beginEditMode(at: center)
        XCTAssertEqual(m.controller.editingCropID, image.id)
        XCTAssertNotNil(m.cropOverlay)
        XCTAssertEqual(m.cropOverlay?.handles.count, 8)
    }

    func testExportSVG() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        XCTAssertTrue(m.exportSVG().contains("<svg"))
    }

    func testZoomInOutReset() {
        let m = EditorModel()
        m.canvasSize = CGSize(width: 1000, height: 800)
        m.zoomIn()
        XCTAssertGreaterThan(m.viewport.zoom, 1)
        m.resetZoom()
        XCTAssertEqual(m.viewport.zoom, 1, accuracy: 1e-9)
        m.zoomOut()
        XCTAssertLessThan(m.viewport.zoom, 1)
    }

    func testZoomToFit() {
        let m = EditorModel()
        m.canvasSize = CGSize(width: 400, height: 400)
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 800, y: 800))
        m.zoomToFit()
        // An 800-wide shape fits into a 400 canvas → zoom < 1.
        XCTAssertLessThan(m.viewport.zoom, 1)
    }

    func testCopyCutPasteRoundTrip() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40))
        m.controller.selectAll()
        m.copy()
        m.paste()
        XCTAssertEqual(m.controller.scene.visibleElements.count, 2)
    }

    func testCommandDispatch() {
        let m = EditorModel()
        m.run(.selectTool(.ellipse))
        XCTAssertEqual(m.activeTool, .ellipse)
        m.run(.selectTool(.rectangle))
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 30, y: 30))
        m.run(.selectAll)
        m.run(.duplicate)
        XCTAssertEqual(m.controller.scene.visibleElements.count, 2)
        m.run(.undo)
        XCTAssertEqual(m.controller.scene.visibleElements.count, 1)
    }

    func testDocumentSaveLoadRoundTrip() throws {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 40))
        let data = m.documentData()
        XCTAssertNotNil(data)

        let m2 = EditorModel()
        try m2.loadDocument(XCTUnwrap(data))
        XCTAssertEqual(m2.controller.scene.visibleElements.count, 1)
    }

    private func tempStore() -> LibraryStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lib-\(UUID().uuidString).excalidrawlib")
        return LibraryStore(url: url)
    }

    func testLibraryAddAndStamp() {
        let m = EditorModel(libraryStore: tempStore())
        m.canvasSize = CGSize(width: 400, height: 400)
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        m.controller.selectAll()
        m.addSelectionToLibrary()
        XCTAssertEqual(m.library.count, 1)
        XCTAssertNotNil(m.libraryThumbnail(0))

        let before = m.controller.scene.visibleElements.count
        m.stampLibraryItem(0)
        XCTAssertEqual(m.controller.scene.visibleElements.count, before + 1)
        XCTAssertFalse(m.showLibrary)
    }

    func testLibraryPersistsAcrossInstances() {
        let store = tempStore()
        let m = EditorModel(libraryStore: store)
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        m.controller.selectAll()
        m.addSelectionToLibrary()

        // A fresh model backed by the same store reloads the saved item.
        let reloaded = EditorModel(libraryStore: store)
        XCTAssertEqual(reloaded.library.count, 1)

        m.removeLibraryItem(0)
        XCTAssertTrue(EditorModel(libraryStore: store).library.isEmpty)
    }

    func testLibraryImportExportRoundTrip() throws {
        let m = EditorModel(libraryStore: tempStore())
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        m.controller.selectAll()
        m.addSelectionToLibrary()
        let data = try XCTUnwrap(m.exportLibraryData())

        let other = EditorModel(libraryStore: tempStore())
        try other.importLibrary(data)
        XCTAssertEqual(other.library.count, 1)
    }

    func testLinkPromptAndCommit() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        m.controller.selectAll()
        m.promptLink()
        XCTAssertTrue(m.showLinkPrompt)
        XCTAssertEqual(m.linkText, "")
        m.linkText = "https://example.com"
        m.commitLink()
        XCTAssertFalse(m.showLinkPrompt)
        XCTAssertEqual(m.controller.selectedElements.first?.base.link, "https://example.com")

        m.promptLink()
        XCTAssertEqual(m.linkText, "https://example.com") // pre-fills existing link
        m.linkText = ""
        m.commitLink()
        XCTAssertNil(m.controller.selectedElements.first?.base.link)
    }

    func testElbowToggleCreatesOrthogonalArrow() {
        let m = EditorModel()
        m.setElbowed(true)
        XCTAssertTrue(m.elbowed)
        m.select(tool: .arrow)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 80))
        guard case let .arrow(props) = m.controller.scene.visibleElements.first?.kind else { return XCTFail("arrow") }
        XCTAssertTrue(props.elbowed)
        // Routed orthogonal: every segment is axis-aligned.
        for i in 0 ..< (props.points.count - 1) {
            let a = props.points[i], b = props.points[i + 1]
            XCTAssertTrue(abs(a.x - b.x) < 1e-6 || abs(a.y - b.y) < 1e-6)
        }
    }

    func testLocaleSwitchingTranslatesAndSetsDirection() {
        let m = EditorModel()
        XCTAssertEqual(m.t("labels.copy"), "Copy")
        XCTAssertEqual(m.layoutDirection, .leftToRight)
        m.setLocale("es")
        XCTAssertEqual(m.t("labels.copy"), "Copiar")
        m.setLocale("ar")
        XCTAssertEqual(m.t("labels.copy"), "نسخ")
        XCTAssertEqual(m.layoutDirection, .rightToLeft)
    }

    func testResetElbowShapeFromModel() {
        let props = ArrowProperties(
            points: [Point(0, 0), Point(50, 0), Point(50, 100), Point(150, 100)],
            endArrowhead: .arrow, elbowed: true,
            fixedSegments: [FixedSegment(start: Point(50, 0), end: Point(50, 100), index: 2)]
        )
        var base = BaseProperties(id: "a"); base.width = 150; base.height = 100
        let scene = ExcalidrawModel.Scene(elements: [ExcalidrawElement(base: base, kind: .arrow(props))])
        let m = EditorModel(scene: scene)
        m.controller.selectAll()
        XCTAssertTrue(m.canResetElbowShape)
        m.resetElbowShape()
        XCTAssertFalse(m.canResetElbowShape)
    }

    func testAddFlowchartNodeFromModel() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 60))
        m.controller.selectAll()
        XCTAssertTrue(m.addFlowchartNode(.right))
        // source + new node + connecting arrow.
        XCTAssertEqual(m.controller.scene.visibleElements.count, 3)
    }

    func testAddFlowchartNodeRequiresSingleSelection() {
        let m = EditorModel()
        XCTAssertFalse(m.addFlowchartNode(.right)) // nothing selected
    }

    func testThemeAndZenToggles() {
        let m = EditorModel()
        XCTAssertEqual(m.theme, .light)
        m.toggleTheme()
        XCTAssertEqual(m.theme, .dark)
        XCTAssertFalse(m.zenMode)
        m.toggleZenMode()
        XCTAssertTrue(m.zenMode)
    }

    func testZoomPercent() {
        let m = EditorModel(viewport: Viewport(zoom: 1.5))
        XCTAssertEqual(m.zoomPercent, 150)
    }

    func testExport() {
        let m = EditorModel()
        XCTAssertNil(m.exportPNG()) // empty scene
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 80, y: 50))
        XCTAssertNotNil(m.exportPNG())
    }
}
