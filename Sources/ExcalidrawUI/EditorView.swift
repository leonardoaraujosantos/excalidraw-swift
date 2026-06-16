import ExcalidrawEditor
import ExcalidrawModel
import ExcalidrawRender
import PhotosUI
import SwiftUI

/// The adaptive single-user editor. The tool/action toolbar sits at the top on
/// regular widths (iPad) and the bottom on compact widths (iPhone). A footer
/// carries zoom, theme, zen, and the command palette. Pointer input comes from
/// `PointerInputView` (raw `UITouch`) on iOS.
public struct EditorView: View {
    @StateObject private var model: EditorModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var exported = false
    @State private var photoItem: PhotosPickerItem?
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
                        linearPoints: model.controller.linearEditHandles()?.points ?? [],
                        linearMidpoints: model.controller.linearEditHandles()?.midpoints ?? []
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
        Button("Copy") { model.copy() }
        Button("Cut") { model.cut() }
        Button("Paste") { model.paste() }
        Button("Duplicate") { model.duplicate() }
        Button("Bring to Front") { model.bringToFront() }
        Button("Send to Back") { model.sendToBack() }
        Divider()
        Button("Delete", role: .destructive) { model.deleteSelected() }
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
                if exported {
                    Text("Exported").foregroundStyle(.secondary).accessibilityIdentifier("exported-confirmation")
                }
            }.padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(.thinMaterial)
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
            Button { model.toggleSnap() } label: {
                Image(systemName: model.snapEnabled ? "ruler.fill" : "ruler")
            }.accessibilityIdentifier("snap-toggle")
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
