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

    func testTappingOutsideCommitsTheTextBeingEdited() {
        let m = EditorModel()
        m.select(tool: .text)
        m.pointer(.down, at: CGPoint(x: 20, y: 20)) // place + begin editing
        XCTAssertNotNil(m.editingTextID)
        m.editingText = "Hi"

        // A tap elsewhere commits the text (no Done button) and is consumed.
        m.pointer(.down, at: CGPoint(x: 300, y: 300))

        XCTAssertNil(m.editingTextID) // editor dismissed
        guard case let .text(props) = m.controller.scene.visibleElements.first?.kind else {
            return XCTFail("expected a committed text element")
        }
        XCTAssertEqual(props.text, "Hi")
        // The dismissing tap must not create a second element.
        XCTAssertEqual(m.controller.scene.visibleElements.count, 1)
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

    func testInsertImageReturnsFileIdAndFiresBrokerHook() throws {
        // The host needs the new image's fileId + bytes to broker them to peers
        // (the collab stream carries only the element). insertImage returns the
        // fileId and hands the same fileId/bytes to onImageInserted.
        let payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let m = EditorModel()
        var brokered: (id: String, bytes: Int, mime: String)?
        m.onImageInserted = { id, d, mime in brokered = (id, d.count, mime) }
        let fileId = try XCTUnwrap(
            m.insertImage(data: data, mimeType: "image/png", viewSize: CGSize(width: 400, height: 400))
        )
        XCTAssertEqual(brokered?.id, fileId)
        XCTAssertEqual(brokered?.bytes, data.count)
        XCTAssertEqual(brokered?.mime, "image/png")
    }

    func testSetImageFileInjectsRemoteBytes() throws {
        // A peer's image arrives as an element with a fileId but no local bytes;
        // the host resolves them out-of-band and injects via setImageFile so the
        // renderer can draw it.
        let payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let m = EditorModel()
        XCTAssertNil(m.controller.scene.files["remote-img"])
        m.setImageFile(id: "remote-img", data: data, mimeType: "image/png")
        XCTAssertNotNil(m.controller.scene.files["remote-img"])
        XCTAssertEqual(m.controller.scene.files["remote-img"]?.mimeType, "image/png")
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

    func testRecognizeSelectedStrokeSnapsToRectangle() {
        let m = EditorModel()
        m.select(tool: .freedraw)
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100),
            CGPoint(x: 0, y: 0)
        ]
        m.pointer(.down, at: corners[0])
        for i in 0 ..< (corners.count - 1) {
            for s in 1 ... 10 {
                let t = CGFloat(s) / 10
                let a = corners[i], b = corners[i + 1]
                m.pointer(.move, at: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        m.pointer(.up, at: corners[0])
        XCTAssertTrue(m.recognizeSelectedStroke())
        if case .rectangle = m.controller.selectedElements.first?.kind {} else { XCTFail("expected rectangle") }
    }

    func testRecognitionRespectsToggle() {
        let m = EditorModel()
        m.shapeRecognitionEnabled = false
        m.select(tool: .freedraw)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
        XCTAssertFalse(m.recognizeSelectedStroke()) // disabled → no-op
    }

    func testStickyNoteToolCreatesNoteAndEditsText() {
        let m = EditorModel()
        m.select(tool: .postit)
        m.pointer(.down, at: CGPoint(x: 40, y: 40))
        // A note (container + bound text) is created and its label is being edited.
        XCTAssertEqual(m.controller.scene.visibleElements.count, 2)
        XCTAssertNotNil(m.editingTextID)
        m.editingText = "Todo"
        m.commitText()
        let text = m.controller.scene.visibleElements.first { if case .text = $0.kind { return true }; return false }
        guard case let .text(props) = text?.kind else { return XCTFail("text") }
        XCTAssertEqual(props.text, "Todo")
        XCTAssertNotNil(props.containerId)
    }

    func testDoubleTapNoteEditsItsText() {
        let m = EditorModel()
        let note = m.controller.createStickyNote(at: Point(0, 0))
        m.controller.setText(id: note.text, "hi")
        m.beginEditMode(at: CGPoint(x: 80, y: 80)) // double-tap centre
        XCTAssertEqual(m.editingTextID, note.text)
        XCTAssertEqual(m.editingText, "hi")
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

    func testSloppinessAppliesToSelection() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 40))
        m.setRoughness(2)
        XCTAssertEqual(m.controller.selectedElements.first?.base.roughness, 2)
        XCTAssertEqual(m.controller.currentItem.roughness, 2)
    }

    func testEdgesToggleSetsAndClearsRoundness() {
        let m = EditorModel()
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 40))
        m.setEdgesRound(false)
        XCTAssertNil(m.controller.selectedElements.first?.base.roundness)
        m.setEdgesRound(true)
        XCTAssertEqual(m.controller.selectedElements.first?.base.roundness?.type, RoundnessType.adaptiveRadius)
    }

    func testChartInputCommitsABarChart() {
        let m = EditorModel()
        m.canvasSize = CGSize(width: 800, height: 600)
        m.showChartInput = true
        m.chartValuesText = "10, 20, 30"
        m.chartKind = .bar
        m.commitChart()
        XCTAssertFalse(m.showChartInput)
        let bars = m.controller.scene.visibleElements.filter {
            if case .rectangle = $0.kind { return true }; return false
        }
        XCTAssertEqual(bars.count, 3)
    }

    func testChartInputIgnoresGarbage() {
        let m = EditorModel()
        m.chartValuesText = "not numbers"
        m.commitChart()
        XCTAssertTrue(m.controller.scene.visibleElements.isEmpty)
    }

    func testTableToolCreatesGridAndAddsRow() {
        let m = EditorModel()
        m.select(tool: .table)
        m.pointer(.down, at: CGPoint(x: 40, y: 40))
        XCTAssertEqual(m.activeTool, .selection) // one-shot tool reverts
        XCTAssertEqual(m.controller.scene.visibleElements.count, 18) // 3×3 cells × (rect + text)
        XCTAssertNotNil(m.selectedTableGroup)
        m.addTableRow()
        XCTAssertEqual(m.controller.scene.visibleElements.count, 18 + 6) // +3 cells × 2
    }

    func testLayeredRenderingDuringInteraction() {
        let m = EditorModel()
        m.canvasSize = CGSize(width: 400, height: 300)
        // Two committed rectangles.
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 50))
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 100, y: 10), to: CGPoint(x: 150, y: 50))

        // Idle: no static layer (full render path).
        XCTAssertNil(m.staticLayerImage(size: CGSize(width: 400, height: 300)))

        // Begin moving the second rectangle: it becomes the dynamic layer; the
        // static layer caches everything else.
        m.select(tool: .selection)
        m.pointer(.down, at: CGPoint(x: 100, y: 30)) // on the second rectangle's left edge
        XCTAssertFalse(m.dynamicIDs.isEmpty)
        let image = m.staticLayerImage(size: CGSize(width: 400, height: 300))
        XCTAssertNotNil(image)
        // Cached: a second request during the same interaction returns the same image.
        XCTAssertTrue(image === m.staticLayerImage(size: CGSize(width: 400, height: 300)))

        m.pointer(.move, at: CGPoint(x: 200, y: 120))
        m.pointer(.up, at: CGPoint(x: 200, y: 120))
        // Interaction ended: back to the full-render path.
        XCTAssertTrue(m.dynamicIDs.isEmpty)
        XCTAssertNil(m.staticLayerImage(size: CGSize(width: 400, height: 300)))
    }

    private func pixels(_ image: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buffer
    }

    func testOffscreenLayerOrientationMatchesTopLeftRender() throws {
        // Regression: the offscreen static/gesture image must have the same
        // orientation as the live `withCGContext` (top-left) render, else the
        // cached layer composites upside-down during move/pan/zoom.
        var rect = BaseProperties(id: "r"); rect.x = 40; rect.y = 20; rect.width = 200; rect.height = 40
        rect.backgroundColor = "#ff0000"; rect.fillStyle = .solid; rect.seed = 3
        let scene = ExcalidrawModel.Scene(elements: [ExcalidrawElement(base: rect, kind: .rectangle)])
        let (w, h) = (400, 300)
        let m = EditorModel(scene: scene)
        m.canvasSize = CGSize(width: w, height: h)
        m.displayScale = 1

        m.beginViewportGesture()
        let snapshot = try XCTUnwrap(m.gestureSnapshot(size: CGSize(width: w, height: h)))

        // Reference: render the same scene into a top-left-oriented context.
        let ref = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ref.translateBy(x: 0, y: CGFloat(h)); ref.scaleBy(x: 1, y: -1)
        SceneRenderer().render(scene, in: ref, viewport: Viewport(), size: CGSize(width: w, height: h))
        let reference = try XCTUnwrap(ref.makeImage())

        let snap = pixels(snapshot.image, w, h)
        let expected = pixels(reference, w, h)
        var differing = 0
        for i in stride(from: 0, to: snap.count, by: 4) where abs(Int(snap[i]) - Int(expected[i])) > 24 {
            differing += 1
        }
        XCTAssertLessThan(Double(differing) / Double(w * h), 0.02, "offscreen layer is mis-oriented vs top-left render")
    }

    func testViewportGestureSnapshotTracksPanAndZoom() {
        let m = EditorModel(viewport: Viewport(scrollX: 0, scrollY: 0, zoom: 1))
        m.canvasSize = CGSize(width: 400, height: 300)
        m.select(tool: .rectangle)
        draw(m, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 60))

        // Idle: no gesture snapshot.
        XCTAssertNil(m.gestureSnapshot(size: CGSize(width: 400, height: 300)))

        m.beginViewportGesture()
        XCTAssertTrue(m.isViewportGesturing)
        // Pan by (10, 20) view points at zoom 1 (scroll += translation/zoom).
        m.panZoom(translation: CGSize(width: 10, height: 20), scale: 1)
        let panned = m.gestureSnapshot(size: CGSize(width: 400, height: 300))
        XCTAssertNotNil(panned)
        XCTAssertEqual(panned?.rect.origin.x ?? .nan, 10, accuracy: 1e-6)
        XCTAssertEqual(panned?.rect.origin.y ?? .nan, 20, accuracy: 1e-6)
        XCTAssertEqual(panned?.rect.width ?? .nan, 400, accuracy: 1e-6) // scale 1 → unchanged size

        // Zooming IN past the snapshot → nil, so the canvas re-renders crisply.
        m.panZoom(translation: .zero, scale: 2)
        XCTAssertNil(m.gestureSnapshot(size: CGSize(width: 400, height: 300)))

        // Zooming OUT keeps using the snapshot (downscale stays crisp + cheap).
        m.panZoom(translation: .zero, scale: 0.25) // back below the start zoom
        let zoomedOut = m.gestureSnapshot(size: CGSize(width: 400, height: 300))
        XCTAssertNotNil(zoomedOut)
        XCTAssertLessThan(zoomedOut?.rect.width ?? .infinity, 400) // scaled down

        m.endViewportGesture()
        XCTAssertFalse(m.isViewportGesturing)
        XCTAssertNil(m.gestureSnapshot(size: CGSize(width: 400, height: 300)))
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
