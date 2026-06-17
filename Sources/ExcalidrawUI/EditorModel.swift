import ExcalidrawEditor
import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import ExcalidrawRender
import SwiftUI

/// Bridges the pure `EditorController` to SwiftUI: forwards pointer events
/// (converting view → scene coordinates), owns the viewport, and republishes a
/// `revision` so the canvas redraws after each change.
@MainActor
public final class EditorModel: ObservableObject {
    public let controller: EditorController
    /// Active scene renderer (Core Graphics by default; swappable to Metal via
    /// `setRenderer`). See `EditorModel+Renderer.swift`.
    var renderer: SceneRendering = SceneRenderer()
    /// Core Graphics renderer for the Metal-hybrid text/overlay pass.
    let cgOverlayRenderer = SceneRenderer()
    /// Ephemeral fading trails for the laser pointer and eraser.
    public let trail = TrailStore()
    @Published public internal(set) var rendererKind: RendererKind = .coreGraphics

    @Published public var viewport: Viewport
    @Published public internal(set) var revision = 0
    @Published public var activeTool: Tool = .selection
    @Published public var strokeColor: String = "#1e1e1e"
    @Published public var strokeWidth: Double = 2
    @Published public var backgroundColor: String = "transparent"
    @Published public var fillStyle: ExcalidrawModel.FillStyle = .hachure
    @Published public var strokeStyle: ExcalidrawModel.StrokeStyle = .solid
    @Published public var opacity: Double = 100
    /// Hand-drawn roughness: 0 = architect, 1 = artist, 2 = cartoonist.
    @Published public var roughness: Double = 1
    /// Rounded edges/corners (linear splines, rounded rectangles).
    @Published public var edgesRound: Bool = true
    @Published public var elbowed: Bool = false
    @Published public var fontFamily: Int = FontFamily.default
    @Published public var fontSize: Double = 20

    /// On-canvas text editing state.
    @Published public var editingTextID: String?
    @Published public var editingText: String = ""
    @Published public var editingTextOrigin: CGPoint = .zero

    /// Last known canvas size in points, for zoom-to-fit and image centring.
    public var canvasSize: CGSize = .init(width: 1024, height: 768)
    /// Local clipboard fallback when no system pasteboard is wired.
    var clipboard: Data?

    @Published public var theme: Theme = .light
    @Published public var zenMode = false
    @Published public var showCommandPalette = false
    @Published public var showBenchmark = false
    @Published public var snapEnabled = false {
        didSet { controller.snapEnabled = snapEnabled }
    }

    public func toggleSnap() {
        snapEnabled.toggle()
        revision += 1
    }

    public var zoomPercent: Int {
        Int((viewport.zoom * 100).rounded())
    }

    /// A short stats string for the current selection (size in points).
    public var selectionStats: String? {
        guard let bounds = controller.selectionBounds else { return nil }
        return "\(Int(bounds.width.rounded())) × \(Int(bounds.height.rounded()))"
    }

    public init(
        scene: ExcalidrawModel.Scene = ExcalidrawModel.Scene(),
        viewport: Viewport = Viewport(),
        libraryStore: LibraryStore? = nil
    ) {
        controller = EditorController(scene: scene)
        controller.zoom = viewport.zoom
        self.viewport = viewport
        self.libraryStore = libraryStore ?? LibraryStore.defaultStore()
        library = (try? self.libraryStore.load()) ?? []
    }

    // MARK: Pointer input (view coordinates in)

    public func pointer(
        _ phase: PointerPhase, at viewPoint: CGPoint, type: PointerType = .mouse,
        pressure: Double = 0.5, shift: Bool = false, alt: Bool = false, toggle: Bool = false
    ) {
        let scenePoint = viewport.viewToScene(Point(viewPoint.x, viewPoint.y))

        // Tap-to-create tools (text/post-it/table) and the ephemeral laser
        // pointer are handled out-of-line; `handlePointerTool` returns true when
        // it fully handled the event (no element/selection forwarding needed).
        if handlePointerTool(phase: phase, viewPoint: viewPoint, scenePoint: scenePoint) { return }

        let event = PointerEvent(
            scenePoint: scenePoint, phase: phase, type: type,
            pressure: pressure, shift: shift, alt: alt, toggleSelection: toggle
        )
        switch phase {
        case .down:
            controller.pointerDown(event)
            if activeTool == .freedraw { isDrawingFreehand = true }
            beginDynamicLayer()
        case .move: controller.pointerMove(event)
        case .up:
            controller.pointerUp(event)
            isDrawingFreehand = false
            endDynamicLayer()
            activeTool = controller.activeTool // tool may revert after creating
        }
        revision += 1
    }

    // MARK: Layered rendering (Phase 7.5 Stage B)

    public var displayScale: Double = 2 // offscreen-image scale; set from the canvas
    let staticLayer = StaticLayerCache()
    /// In-flight elements (moved/created + bound arrows + frame children); the
    /// rest is the cached static layer. (Methods live in `EditorModel+Rendering`.)
    var dynamicIDs: Set<String> = []
    var staticToken = 0

    /// Stage C: pan/zoom snapshots the scene once and composites it transformed.
    let gestureLayer = StaticLayerCache()
    var isViewportGesturing = false
    var gestureViewport = Viewport()

    // MARK: Viewport (two-finger pan / pinch)

    public func panZoom(translation: CGSize, scale: Double) {
        var v = viewport
        let range = ExcalidrawRender.zoomRange
        v.zoom = min(max(viewport.zoom * scale, range.lowerBound), range.upperBound)
        v.scrollX = viewport.scrollX + translation.width / v.zoom
        v.scrollY = viewport.scrollY + translation.height / v.zoom
        viewport = v
        controller.zoom = v.zoom
        revision += 1
    }

    // MARK: Commands

    public func select(tool: Tool) {
        controller.setTool(tool)
        activeTool = tool
        revision += 1
    }

    public func setStrokeColor(_ color: String) {
        strokeColor = color
        controller.currentItem.strokeColor = color
        applyToSelection { $0.base.strokeColor = color }
    }

    public func setStrokeWidth(_ width: Double) {
        strokeWidth = width
        controller.currentItem.strokeWidth = width
        applyToSelection { $0.base.strokeWidth = width }
    }

    public func setBackgroundColor(_ color: String) {
        backgroundColor = color
        controller.currentItem.backgroundColor = color
        applyToSelection { $0.base.backgroundColor = color }
    }

    public func setFillStyle(_ style: ExcalidrawModel.FillStyle) {
        fillStyle = style
        controller.currentItem.fillStyle = style
        applyToSelection { $0.base.fillStyle = style }
    }

    public func setStrokeStyle(_ style: ExcalidrawModel.StrokeStyle) {
        strokeStyle = style
        controller.currentItem.strokeStyle = style
        applyToSelection { $0.base.strokeStyle = style }
    }

    public func setOpacity(_ value: Double) {
        opacity = value
        controller.currentItem.opacity = value
        applyToSelection { $0.base.opacity = value }
    }

    /// Set the hand-drawn roughness (0 architect, 1 artist, 2 cartoonist).
    public func setRoughness(_ value: Double) {
        roughness = value
        controller.currentItem.roughness = value
        applyToSelection { $0.base.roughness = value }
    }

    /// Toggle rounded edges/corners on the selection and for new elements.
    public func setEdgesRound(_ round: Bool) {
        edgesRound = round
        controller.currentItem.roundEdges = round
        applyToSelection { element in
            element.base.roundness = round ? Roundness(type: roundnessType(for: element)) : nil
        }
    }

    private func roundnessType(for element: ExcalidrawElement) -> Int {
        switch element.kind {
        case .line, .arrow: RoundnessType.proportionalRadius
        default: RoundnessType.adaptiveRadius
        }
    }

    public func setFontFamily(_ family: Int) {
        fontFamily = family
        controller.currentItem.fontFamily = family
        controller.updateSelectedText { $0.fontFamily = family }
        revision += 1
    }

    public func setFontSize(_ size: Double) {
        fontSize = size
        controller.currentItem.fontSize = size
        controller.updateSelectedText { $0.fontSize = size }
        revision += 1
    }

    public func setElbowed(_ elbowed: Bool) {
        self.elbowed = elbowed
        controller.setElbowed(elbowed)
        revision += 1
    }

    // MARK: Shape recognition

    /// When enabled, holding still at the end of a freehand stroke snaps it to a
    /// recognized shape (square/circle/triangle/line/diamond).
    @Published public var shapeRecognitionEnabled = true

    /// Whether a freehand stroke is currently in progress (for the dwell timer).
    @Published public private(set) var isDrawingFreehand = false

    /// Snap the just-drawn (selected) freehand stroke to a recognized shape.
    /// Triggered by holding the pen still; no-op if recognition is off or the
    /// selection isn't a recognizable freedraw.
    @discardableResult
    public func recognizeSelectedStroke() -> Bool {
        guard shapeRecognitionEnabled, controller.selectedIDs.count == 1,
              let id = controller.selectedIDs.first, controller.recognizeFreedraw(id) != nil else { return false }
        revision += 1
        return true
    }

    // MARK: Flowchart

    /// Spawn a flowchart node linked to the single selected node in `direction`
    /// (default right, as bound to the Tab key) and select it.
    @discardableResult
    public func addFlowchartNode(_ direction: FlowchartDirection = .right) -> Bool {
        guard controller.selectedIDs.count == 1, let id = controller.selectedIDs.first,
              controller.addFlowchartNode(from: id, direction: direction) != nil else { return false }
        revision += 1
        return true
    }

    // MARK: Localization

    @Published public var locale: ExcalidrawModel.Locale = Localization.english

    /// Translate a UI string key in the current locale.
    public func t(_ key: String) -> String {
        Localization.string(key, in: locale)
    }

    /// Switch the UI locale by language tag (e.g. `"es"`, `"ar"`).
    public func setLocale(_ tag: String) {
        locale = Localization.locale(for: tag)
        revision += 1
    }

    /// Layout direction for the current locale, for RTL mirroring.
    public var layoutDirection: LayoutDirection {
        locale.isRTL ? .rightToLeft : .leftToRight
    }

    /// Whether any selected elbow arrow has pinned segments (shows "Reset arrow
    /// shape" in the menu).
    public var canResetElbowShape: Bool {
        controller.selectedElements.contains { controller.hasFixedSegments($0.id) }
    }

    /// Release pinned segments on every selected elbow arrow and re-route them.
    public func resetElbowShape() {
        for element in controller.selectedElements {
            controller.resetElbowShape(element.id)
        }
        revision += 1
    }

    // MARK: Element linking

    @Published public var showLinkPrompt = false
    @Published public var linkText = ""

    public func promptLink() {
        linkText = controller.selectionLink ?? ""
        showLinkPrompt = true
    }

    public func commitLink() {
        controller.setLink(linkText)
        showLinkPrompt = false
        revision += 1
    }

    // MARK: Action passthroughs

    public func group() {
        controller.group(); revision += 1
    }

    public func duplicate() {
        controller.duplicate(); revision += 1
    }

    public func bringToFront() {
        controller.reorder(.front); revision += 1
    }

    public func sendToBack() {
        controller.reorder(.back); revision += 1
    }

    public func align(_ alignment: EditorController.Alignment) {
        controller.align(alignment); revision += 1
    }

    public func undo() {
        controller.undo(); revision += 1
    }

    public func redo() {
        controller.redo(); revision += 1
    }

    public func deleteSelected() {
        controller.deleteSelected(); revision += 1
    }

    // MARK: Clipboard

    public func copy() {
        guard let data = controller.copyData() else { return }
        clipboard = data
        Pasteboard.write(data)
    }

    public func cut() {
        copy()
        controller.deleteSelected()
        revision += 1
    }

    public func paste() {
        guard let data = Pasteboard.read() ?? clipboard else { return }
        controller.paste(data)
        revision += 1
    }

    // MARK: Zoom

    public func zoomIn() {
        setZoom(viewport.zoom * 1.2, anchor: canvasCenter)
    }

    public func zoomOut() {
        setZoom(viewport.zoom / 1.2, anchor: canvasCenter)
    }

    public func resetZoom() {
        setZoom(1, anchor: canvasCenter)
    }

    /// Fit all content into the canvas with margin.
    public func zoomToFit() {
        guard let bounds = controller.selectionOrContentBounds else { return }
        let margin = 0.9
        let zoomX = canvasSize.width / max(bounds.width, 1)
        let zoomY = canvasSize.height / max(bounds.height, 1)
        let range = ExcalidrawRender.zoomRange
        let zoom = min(max(min(zoomX, zoomY) * margin, range.lowerBound), range.upperBound)
        var v = viewport
        v.zoom = zoom
        // Centre the content.
        v.scrollX = canvasSize.width / (2 * zoom) - (bounds.minX + bounds.maxX) / 2
        v.scrollY = canvasSize.height / (2 * zoom) - (bounds.minY + bounds.maxY) / 2
        viewport = v
        controller.zoom = zoom
        revision += 1
    }

    private var canvasCenter: Point {
        Point(canvasSize.width / 2, canvasSize.height / 2)
    }

    /// Zoom about a view-space anchor, keeping the scene point under it fixed.
    private func setZoom(_ target: Double, anchor: Point) {
        let range = ExcalidrawRender.zoomRange
        let zoom = min(max(target, range.lowerBound), range.upperBound)
        let scene = viewport.viewToScene(anchor)
        var v = viewport
        v.zoom = zoom
        v.scrollX = anchor.x / zoom - scene.x
        v.scrollY = anchor.y / zoom - scene.y
        viewport = v
        controller.zoom = zoom
        revision += 1
    }

    // MARK: Command dispatch (shortcuts + palette)

    public func run(_ command: EditorCommand) {
        switch command {
        case let .selectTool(tool): select(tool: tool)
        case .undo: undo()
        case .redo: redo()
        case .delete: deleteSelected()
        case .duplicate: duplicate()
        case .selectAll: controller.selectAll(); revision += 1
        case .group: group()
        case .ungroup: controller.ungroup(); revision += 1
        case .copy: copy()
        case .cut: cut()
        case .paste: paste()
        case .bringToFront: bringToFront()
        case .sendToBack: sendToBack()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .zoomToFit: zoomToFit()
        case .resetZoom: resetZoom()
        }
    }

    public func exportPNG() -> Data? {
        Exporter.pngData(controller.scene)
    }

    public func exportSVG() -> String {
        SVGExporter.svg(controller.scene)
    }

    // MARK: Document persistence

    /// Serialize the current scene as a `.excalidraw` document.
    public func documentData() -> Data? {
        try? SceneDocument.encode(controller.scene)
    }

    /// Load a `.excalidraw` document, replacing the current scene.
    public func loadDocument(_ data: Data) {
        guard let scene = try? SceneDocument.decode(data) else { return }
        controller.load(scene: scene)
        revision += 1
    }

    /// If `pngData` is an exported PNG with an embedded scene, open it as the
    /// current drawing (the PNG scene-embed round-trip). Returns whether it did.
    @discardableResult
    public func openSceneFromPNG(_ pngData: Data) -> Bool {
        guard let scene = PNGSceneEmbed.extractScene(from: pngData) else { return false }
        controller.load(scene: scene)
        activeTool = .selection
        controller.setTool(.selection)
        revision += 1
        return true
    }

    // MARK: Library

    @Published public var library: [[ExcalidrawElement]] = []
    @Published public var showLibrary = false
    private let libraryStore: LibraryStore

    /// Add the current selection to the library as a reusable item.
    public func addSelectionToLibrary() {
        let elements = controller.selectedElements
        guard !elements.isEmpty else { return }
        library.append(elements)
        persistLibrary()
    }

    /// Remove library item `index` and persist.
    public func removeLibraryItem(_ index: Int) {
        guard library.indices.contains(index) else { return }
        library.remove(at: index)
        persistLibrary()
    }

    /// Merge items from an imported `.excalidrawlib` payload and persist.
    public func importLibrary(_ data: Data) throws {
        let imported = try ExcalidrawLibrary.decode(from: data).items
        library.append(contentsOf: imported)
        persistLibrary()
    }

    /// Serialize the whole library as an `.excalidrawlib` payload for export.
    public func exportLibraryData() -> Data? {
        try? ExcalidrawLibrary(items: library).encoded()
    }

    private func persistLibrary() {
        try? libraryStore.save(library)
    }

    /// Stamp library item `index` near the centre of the canvas.
    public func stampLibraryItem(_ index: Int) {
        guard library.indices.contains(index) else { return }
        let center = viewport.viewToScene(Point(canvasSize.width / 2, canvasSize.height / 2))
        controller.insertLibraryItem(library[index], at: center)
        showLibrary = false
        revision += 1
    }

    /// A thumbnail of library item `index` for the panel.
    public func libraryThumbnail(_ index: Int) -> CGImage? {
        guard library.indices.contains(index) else { return nil }
        return Exporter.cgImage(ExcalidrawModel.Scene(elements: library[index]), options: .init(scale: 1, padding: 6))
    }

    // MARK: Linear / crop editing

    /// Enter an edit mode at a view point (e.g. double-tap): point-editing for a
    /// line/arrow, or crop mode for an image.
    public func beginEditMode(at viewPoint: CGPoint) {
        let scenePoint = viewport.viewToScene(Point(viewPoint.x, viewPoint.y))
        // A note (container with bound text) edits its label.
        if let hit = controller.boundTextHit(at: scenePoint) {
            beginEditingBoundText(hit.text, at: viewPoint)
            return
        }
        if controller.beginLinearEdit(at: scenePoint) { revision += 1; return }
        guard let hit = controller.imageHit(at: scenePoint),
              let image = ImageDecoder.decode(dataURL: hit.dataURL) else { return }
        if controller.beginCropEdit(
            id: hit.id, naturalWidth: Double(image.width), naturalHeight: Double(image.height)
        ) { revision += 1 }
    }

    /// Back-compat alias retained for callers/tests; forwards to `beginEditMode`.
    public func beginLinearEdit(at viewPoint: CGPoint) {
        beginEditMode(at: viewPoint)
    }

    /// Edit-overlay handles for the element in linear/segment edit mode. Elbow
    /// arrows expose draggable segment midpoints; other lines/arrows expose
    /// their vertices and insert-midpoints.
    public var linearOverlay: (points: [Point], midpoints: [Point]) {
        guard let id = controller.editingLinearID else { return ([], []) }
        if let element = controller.scene.element(id: id),
           case let .arrow(props) = element.kind, props.elbowed {
            return ([], controller.elbowSegmentHandles(id).map(\.point))
        }
        let handles = controller.linearEditHandles()
        return (handles?.points ?? [], handles?.midpoints ?? [])
    }

    /// The crop frame and its handle positions (scene coords) when an image is
    /// in crop mode, for the overlay.
    public var cropOverlay: (frame: BoundingBox, handles: [Point])? {
        guard let frame = controller.cropFrame(), let handles = controller.cropEditHandles() else { return nil }
        return (frame, handles)
    }

    // MARK: Text editing

    func beginTextEditing(at viewPoint: CGPoint, scenePoint: Point) {
        let id = controller.createText(at: scenePoint)
        editingTextID = id
        editingText = ""
        editingTextOrigin = viewPoint
        revision += 1
    }

    /// Revert to the selection tool after a one-shot placement (unless locked).
    func revertToSelection() {
        if !controller.toolLocked {
            controller.setTool(.selection)
            activeTool = .selection
        }
    }

    // MARK: Charts

    @Published public var showChartInput = false
    @Published public var chartValuesText = ""
    @Published public var chartKind: ChartKind = .bar

    /// Insert a chart from comma/space/newline-separated numbers in
    /// `chartValuesText`, centred in the view, then close the input.
    public func commitChart() {
        let values = chartValuesText
            .split(whereSeparator: { ", \n\t".contains($0) })
            .compactMap { Double($0) }
        defer { showChartInput = false; chartValuesText = "" }
        guard !values.isEmpty else { return }
        let center = viewport.viewToScene(Point(canvasSize.width / 2, canvasSize.height / 2))
        controller.createChart(
            at: Point(center.x - 120, center.y - 120), values: values, kind: chartKind
        )
        revision += 1
    }

    // MARK: Tables

    /// The table group of the current single-group selection, if any.
    public var selectedTableGroup: String? {
        let groups = Set(controller.selectedElements.compactMap { controller.tableGroupID(of: $0.id) })
        return groups.count == 1 ? groups.first : nil
    }

    public func addTableRow() {
        guard let group = selectedTableGroup else { return }
        controller.addTableRow(group)
        revision += 1
    }

    public func addTableColumn() {
        guard let group = selectedTableGroup else { return }
        controller.addTableColumn(group)
        revision += 1
    }

    /// Drop a sticky note centred on the tap and start editing its label.
    func beginStickyNote(at viewPoint: CGPoint, scenePoint: Point) {
        let note = controller.createStickyNote(at: scenePoint)
        editingTextID = note.text
        editingText = ""
        editingTextOrigin = viewPoint
        if !controller.toolLocked {
            controller.setTool(.selection)
            activeTool = .selection
        }
        revision += 1
    }

    /// Begin editing an existing bound text label (e.g. on double-tapping a note).
    func beginEditingBoundText(_ textID: String, at viewPoint: CGPoint) {
        editingTextID = textID
        if let element = controller.scene.element(id: textID), case let .text(props) = element.kind {
            editingText = props.originalText
        } else {
            editingText = ""
        }
        editingTextOrigin = viewPoint
        revision += 1
    }

    public func commitText() {
        if let id = editingTextID {
            controller.setText(id: id, editingText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        editingTextID = nil
        editingText = ""
        if !controller.toolLocked {
            controller.setTool(.selection)
            activeTool = .selection
        }
        revision += 1
    }

    // MARK: Image insert

    /// Decode image `data`, build a data URL, and insert it centred in the view.
    public func insertImage(data: Data, mimeType: String, viewSize: CGSize) {
        guard let image = ImageDecoder.decode(dataURL: "data:\(mimeType);base64,\(data.base64EncodedString())") else {
            return
        }
        let maxDimension = 320.0
        let scale = min(1, maxDimension / Double(max(image.width, image.height)))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        let center = viewport.viewToScene(Point(viewSize.width / 2, viewSize.height / 2))
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        controller.insertImage(
            dataURL: dataURL, mimeType: mimeType,
            at: Point(center.x - width / 2, center.y - height / 2), width: width, height: height
        )
        activeTool = .selection
        controller.setTool(.selection)
        revision += 1
    }

    /// Apply a style change to the current selection as one undo step.
    func applyToSelection(_ change: (inout ExcalidrawElement) -> Void) {
        controller.updateSelected(change)
        revision += 1
    }
}
