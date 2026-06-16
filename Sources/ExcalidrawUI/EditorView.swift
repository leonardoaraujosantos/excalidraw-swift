import ExcalidrawEditor
import ExcalidrawModel
import ExcalidrawRender
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The adaptive single-user editor. The tool/action toolbar sits at the top on
/// regular widths (iPad) and the bottom on compact widths (iPhone). A footer
/// carries zoom, theme, zen, and the command palette. Pointer input comes from
/// `PointerInputView` (raw `UITouch`) on iOS.
public struct EditorView: View {
    @StateObject private var model: EditorModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var exported = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importingLibrary = false
    @State private var exportingLibrary = false
    @FocusState private var canvasFocused: Bool

    private let tools: [(Tool, String)] = [
        (.selection, "cursorarrow"), (.rectangle, "rectangle"), (.diamond, "diamond"),
        (.ellipse, "circle"), (.arrow, "arrow.up.right"), (.line, "line.diagonal"),
        (.freedraw, "scribble"), (.text, "textformat"), (.frame, "rectangle.dashed"),
        (.eraser, "eraser"), (.hand, "hand.draw")
    ]
    private let palette = ["#1e1e1e", "#e03131", "#2f9e44", "#1971c2", "#f08c00"]
    private let fills = ["transparent", "#ffc9c9", "#b2f2bb", "#a5d8ff", "#ffec99"]

    public init(scene: ExcalidrawModel.Scene = ExcalidrawModel.Scene(), viewport: Viewport = Viewport()) {
        _model = StateObject(wrappedValue: EditorModel(scene: scene, viewport: viewport))
    }

    private var isCompact: Bool {
        sizeClass == .compact
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !model.zenMode, !isCompact { toolbar; propertiesBar }
            canvas
            if !model.zenMode {
                if isCompact { propertiesBar; toolbar }
                footer
            } else {
                zenExitBar
            }
        }
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .sheet(isPresented: $model.showCommandPalette) { commandPalette }
        .sheet(isPresented: $model.showLibrary) { librarySheet }
        .alert("Link", isPresented: $model.showLinkPrompt) {
            TextField("https://example.com", text: $model.linkText)
                .accessibilityIdentifier("link-field")
            Button("Remove", role: .destructive) { model.linkText = ""; model.commitLink() }
            Button("Cancel", role: .cancel) { model.showLinkPrompt = false }
            Button("OK") { model.commitLink() }
        }
        .environment(\.layoutDirection, model.layoutDirection)
    }

    private var librarySheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                    ForEach(Array(model.library.enumerated()), id: \.offset) { index, _ in
                        Button { model.stampLibraryItem(index) } label: {
                            Group {
                                if let cg = model.libraryThumbnail(index) {
                                    Image(decorative: cg, scale: 1).resizable().scaledToFit()
                                } else {
                                    Image(systemName: "square.on.square")
                                }
                            }
                            .frame(width: 90, height: 90)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityIdentifier("library-item-\(index)")
                    }
                }
                .padding()
                if model.library.isEmpty {
                    Text("Select elements and tap “Add” to build your library.")
                        .foregroundStyle(.secondary).padding()
                }
            }
            .navigationTitle("Library")
            .toolbar {
                Button("Add") { model.addSelectionToLibrary() }
                    .accessibilityIdentifier("library-add")
                Menu {
                    Button("Import…") { importingLibrary = true }
                    Button("Export…") { exportingLibrary = true }.disabled(model.library.isEmpty)
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }.accessibilityIdentifier("library-share")
                Button("Done") { model.showLibrary = false }
            }
        }
        .fileImporter(isPresented: $importingLibrary, allowedContentTypes: [.json, .item]) { result in
            guard let url = try? result.get(), url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) { try? model.importLibrary(data) }
        }
        .fileExporter(
            isPresented: $exportingLibrary,
            document: LibraryDocument(data: model.exportLibraryData() ?? Data()),
            contentType: .json,
            defaultFilename: "library.excalidrawlib"
        ) { _ in }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tools, id: \.0) { tool, icon in toolButton(tool, icon) }
                    PhotosPicker(selection: $photoItem, matching: .images) { Image(systemName: "photo") }
                        .accessibilityIdentifier("tool-image")
                    actionButton("doc.on.doc", "duplicate") { model.duplicate() }
                    actionButton("square.3.layers.3d.top.filled", "front") { model.bringToFront() }
                    actionButton("trash", "delete") { model.deleteSelected() }
                }.padding(.leading, 12)
            }
            Divider().frame(height: 24)
            actionButton("arrow.uturn.backward", "undo") { model.undo() }
            actionButton("arrow.uturn.forward", "redo") { model.redo() }
            actionButton("square.and.arrow.up", "export", action: doExport).padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(.thinMaterial)
    }

    private func toolButton(_ tool: Tool, _ icon: String) -> some View {
        Button { model.select(tool: tool) } label: {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .background(model.activeTool == tool ? Color.accentColor.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityIdentifier("tool-\(tool.rawValue)")
    }

    private func actionButton(_ icon: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.accessibilityIdentifier(id)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                _ = model.revision
                context.withCGContext { cg in
                    model.renderer.render(
                        model.controller.scene,
                        in: cg,
                        viewport: model.viewport,
                        size: size,
                        theme: model.theme
                    )
                    let handles = model.controller.transformHandles()
                    InteractiveRenderer.render(
                        selectionBounds: model.controller.selectionBounds,
                        handles: handles.filter { $0.key != .rotation }.map(\.value),
                        rotationHandle: handles[.rotation],
                        selectionRect: model.controller.selectionRect,
                        in: cg, viewport: model.viewport, size: size,
                        snapLinesX: model.controller.snapLinesX,
                        snapLinesY: model.controller.snapLinesY,
                        linearPoints: model.linearOverlay.points,
                        linearMidpoints: model.linearOverlay.midpoints,
                        cropFrame: model.cropOverlay?.frame,
                        cropHandles: model.cropOverlay?.handles ?? []
                    )
                }
            }
            .onAppear { model.canvasSize = geo.size }
            .onChange(of: geo.size) { _, newSize in model.canvasSize = newSize }
        }
        .accessibilityIdentifier("excalidraw-canvas")
        .overlay(inputLayer)
        .overlay(textEditor)
        .contextMenu { contextMenuItems }
        .focusable()
        .focusEffectDisabled()
        .focused($canvasFocused)
        .onKeyPress(phases: .down) { handleKeyPress($0) }
        .onAppear { canvasFocused = true }
        .background(model.theme == .dark ? Color(white: 0.07) : Color.white)
    }

    @ViewBuilder
    private var inputLayer: some View {
        #if canImport(UIKit)
            PointerInputView(model: model)
        #else
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if v.translation == .zero { model.pointer(.down, at: v.startLocation) }
                            model.pointer(.move, at: v.location)
                        }
                        .onEnded { v in model.pointer(.up, at: v.location) }
                )
        #endif
    }

    @ViewBuilder
    private var textEditor: some View {
        if model.editingTextID != nil {
            TextField("Text", text: $model.editingText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .position(x: model.editingTextOrigin.x + 100, y: model.editingTextOrigin.y + 20)
                .accessibilityIdentifier("text-editor")
                .onSubmit { model.commitText() }
                .submitLabel(.done)
                .overlay(alignment: .topTrailing) {
                    Button("Done") { model.commitText() }.accessibilityIdentifier("text-done").padding(4)
                }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(model.t("labels.copy")) { model.copy() }
        Button(model.t("labels.cut")) { model.cut() }
        Button(model.t("labels.paste")) { model.paste() }
        Button(model.t("labels.duplicate")) { model.duplicate() }
        Button(model.t("labels.bringToFront")) { model.bringToFront() }
        Button(model.t("labels.sendToBack")) { model.sendToBack() }
        Button("\(model.t("labels.link"))…") { model.promptLink() }
        if model.canResetElbowShape {
            Button("Reset Arrow Shape") { model.resetElbowShape() }
        }
        Divider()
        Button(model.t("labels.delete"), role: .destructive) { model.deleteSelected() }
    }

    // MARK: Properties / footer

    private var propertiesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                swatches(palette, selected: model.strokeColor, id: "stroke") { model.setStrokeColor($0) }
                Divider().frame(height: 24)
                swatches(fills, selected: model.backgroundColor, id: "bg") { model.setBackgroundColor($0) }
                Divider().frame(height: 24)
                Stepper("W \(Int(model.strokeWidth))", value: Binding(
                    get: { model.strokeWidth }, set: { model.setStrokeWidth($0) }
                ), in: 1 ... 20).fixedSize()
                if showFontControls {
                    Divider().frame(height: 24)
                    fontControls
                }
                if showArrowControls {
                    Divider().frame(height: 24)
                    Toggle(isOn: Binding(get: { model.elbowed }, set: { model.setElbowed($0) })) {
                        Image(systemName: "arrow.turn.right.up")
                    }
                    .toggleStyle(.button)
                    .accessibilityIdentifier("elbow-toggle")
                }
                if exported {
                    Text("Exported").foregroundStyle(.secondary).accessibilityIdentifier("exported-confirmation")
                }
            }.padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(.thinMaterial)
    }

    private let fontFamilies: [(Int, String)] = [
        (FontFamily.excalifont, "Hand-drawn"),
        (FontFamily.helvetica, "Normal"),
        (FontFamily.cascadia, "Code")
    ]

    /// Show font controls when the text tool is active or a text element is selected.
    private var showFontControls: Bool {
        model.activeTool == .text || model.editingTextID != nil
            || model.controller.selectedElements.contains { if case .text = $0.kind { return true }; return false }
    }

    /// Show the elbow toggle when the arrow tool is active or an arrow is selected.
    private var showArrowControls: Bool {
        model.activeTool == .arrow
            || model.controller.selectedElements.contains { if case .arrow = $0.kind { return true }; return false }
    }

    @ViewBuilder
    private var fontControls: some View {
        Menu {
            ForEach(fontFamilies, id: \.0) { id, name in
                Button(name) { model.setFontFamily(id) }
            }
        } label: {
            Image(systemName: "character").accessibilityIdentifier("font-family")
        }
        Stepper("\(Int(model.fontSize))pt", value: Binding(
            get: { model.fontSize }, set: { model.setFontSize($0) }
        ), in: 8 ... 96, step: 2).fixedSize().accessibilityIdentifier("font-size")
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .accessibilityIdentifier("zoom-out")
            Button { model.resetZoom() } label: { Text("\(model.zoomPercent)%").monospacedDigit() }
                .accessibilityIdentifier("zoom-reset")
            Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .accessibilityIdentifier("zoom-in")
            Button { model.zoomToFit() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .accessibilityIdentifier("zoom-fit")
            if let stats = model.selectionStats {
                Text(stats).monospacedDigit().foregroundStyle(.secondary).accessibilityIdentifier("stats")
            }
            Spacer()
            Button { model.shapeRecognitionEnabled.toggle() } label: {
                Image(systemName: model.shapeRecognitionEnabled ? "scribble.variable" : "scribble")
            }.accessibilityIdentifier("shape-recognition-toggle")
            Button { model.toggleSnap() } label: {
                Image(systemName: model.snapEnabled ? "ruler.fill" : "ruler")
            }.accessibilityIdentifier("snap-toggle")
            Button { model.showLibrary = true } label: { Image(systemName: "books.vertical") }
                .accessibilityIdentifier("library")
            Button { model.showCommandPalette = true } label: { Image(systemName: "command") }
                .accessibilityIdentifier("command-palette")
            Button { model.toggleTheme() } label: {
                Image(systemName: model.theme == .dark ? "sun.max" : "moon")
            }.accessibilityIdentifier("theme-toggle")
            Button { model.toggleZenMode() } label: { Image(systemName: "rectangle") }
                .accessibilityIdentifier("zen-toggle")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.thinMaterial)
    }

    private var zenExitBar: some View {
        HStack {
            Spacer()
            Button("Exit Zen") { model.toggleZenMode() }.accessibilityIdentifier("zen-exit").padding(8)
        }
        .background(.thinMaterial)
    }

    private func swatches(
        _ colors: [String], selected: String, id: String, action: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(colors, id: \.self) { color in
                Button { action(color) } label: {
                    Circle().fill(color == "transparent" ? Color.white : Color(hex: color))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(
                            selected == color ? Color.accentColor : .gray.opacity(0.3),
                            lineWidth: selected == color ? 2 : 1
                        ))
                }
                .accessibilityIdentifier("\(id)-\(color)")
            }
        }
    }

    // MARK: Command palette

    private var commandPalette: some View {
        NavigationStack {
            CommandPaletteList { command in
                model.run(command)
                model.showCommandPalette = false
            }
            .navigationTitle("Commands")
        }
    }

    // MARK: Input handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Tab spawns a linked flowchart node to the right of the selected node;
        // ⌥+arrow chooses a direction.
        if press.key == .tab, model.addFlowchartNode(.right) { return .handled }
        if press.modifiers.contains(.option), let direction = flowchartDirection(for: press.key),
           model.addFlowchartNode(direction) { return .handled }

        guard let char = press.characters.first else { return .ignored }
        let chord = KeyChord(
            char,
            command: press.modifiers.contains(.command),
            shift: press.modifiers.contains(.shift),
            option: press.modifiers.contains(.option)
        )
        guard let command = Shortcuts.command(for: chord) else { return .ignored }
        model.run(command)
        return .handled
    }

    private func flowchartDirection(for key: KeyEquivalent) -> FlowchartDirection? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        default: nil
        }
    }

    private func doExport() {
        guard let data = model.exportPNG() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("excalidraw-export.png")
        try? data.write(to: url)
        exported = true
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                model.insertImage(data: data, mimeType: "image/png", viewSize: model.canvasSize)
            }
        }
    }
}

/// A minimal JSON-backed document used to export the library via `.fileExporter`.
struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The command-palette list with a live search field.
private struct CommandPaletteList: View {
    let onRun: (EditorCommand) -> Void
    @State private var query = ""

    var body: some View {
        List(CommandRegistry.search(query)) { command in
            Button(command.title) { onRun(command.command) }
        }
        .searchable(text: $query)
    }
}

extension Color {
    /// Lightweight hex → Color for the palette swatches.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
