import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// The editing state machine: turns scene-space pointer events into element
/// creation, selection, move, resize, and rotation, with undo/redo. Pure Swift
/// (no UIKit) so it is fully unit-testable; the UI layer feeds it `PointerEvent`s
/// and renders `scene` plus the overlay. Mirrors the pointer flow of `App.tsx`.
public final class EditorController {
    // `internal(set)` so the command extension (in a separate file) can mutate.
    public internal(set) var store: Store
    public var activeTool: Tool = .selection
    public var toolLocked = false
    public var currentItem = CurrentItemProperties()
    public var zoom: Double = 1
    public internal(set) var selectedIDs: Set<String> = []
    /// Live box-selection rectangle, for the overlay (nil when not box-selecting).
    public private(set) var selectionRect: BoundingBox?

    /// Object snapping (align to other elements' edges/centres while dragging).
    public var snapEnabled = false
    /// Bind arrow endpoints to nearby shapes on creation; bound arrows follow
    /// their shapes when those move/resize.
    public var bindingEnabled = true
    /// Active snap guide lines during a drag (scene coordinates), for the overlay.
    public private(set) var snapLinesX: [Double] = []
    public private(set) var snapLinesY: [Double] = []

    /// The line/arrow currently in point-edit mode (`nil` when not editing).
    public private(set) var editingLinearID: String?

    /// The image currently in crop mode (`nil` when not cropping), plus the
    /// natural pixel size supplied by the UI when entering the mode.
    public internal(set) var editingCropID: String?
    var cropNaturalSize: (width: Double, height: Double)?
    /// In-flight crop handle drag (captured at pointer-down), separate from the
    /// main interaction enum so the crop code can live in an extension.
    var cropDrag: CropDrag?
    /// In-flight elbow-arrow segment drag (id + segment index), kept outside the
    /// interaction enum so the elbow code can live in an extension.
    var elbowDrag: (id: String, index: Int)?

    struct CropDrag {
        let handle: TransformHandle
        let startBox: BoundingBox
        let startCrop: ImageCrop
        let fullBox: BoundingBox
    }

    let nextID: () -> String
    let nextSeed: () -> Int

    private enum Interaction {
        case idle
        case creating(id: String, origin: Point, moved: Bool)
        case freehand(id: String, origin: Point)
        case draggingLinearPoint(id: String, index: Int)
        case erasing(touched: Set<String>)
        case moving(origin: Point, originals: [String: ExcalidrawElement])
        case boxSelecting(origin: Point)
        case resizing(handle: TransformHandle, bounds: BoundingBox, originals: [String: ExcalidrawElement])
        case rotating(center: Point, originals: [String: ExcalidrawElement])
    }

    private var interaction: Interaction = .idle

    public init(
        scene: Scene = Scene(),
        idProvider: (() -> String)? = nil,
        seedProvider: (() -> Int)? = nil
    ) {
        store = Store(scene: scene)
        var idCounter = 0
        var seedCounter = 1
        nextID = idProvider ?? { idCounter += 1; return "el-\(idCounter)" }
        nextSeed = seedProvider ?? { seedCounter += 1; return seedCounter * 100_001 }
    }

    public var scene: Scene {
        store.scene
    }

    public var canUndo: Bool {
        store.canUndo
    }

    public var canRedo: Bool {
        store.canRedo
    }

    public var selectedElements: [ExcalidrawElement] {
        scene.visibleElements.filter { selectedIDs.contains($0.id) }
    }

    /// Bounding box of the current selection (nil if empty).
    public var selectionBounds: BoundingBox? {
        ElementGeometry.commonBounds(selectedElements)
    }

    /// The selection bounds, or all visible content if nothing is selected
    /// (used by zoom-to-fit).
    public var selectionOrContentBounds: BoundingBox? {
        selectionBounds ?? ElementGeometry.commonBounds(scene.visibleElements)
    }

    /// Handle positions for the current selection, shown by the overlay when the
    /// selection tool is active. Suppressed during line point-editing.
    public func transformHandles() -> [TransformHandle: Point] {
        guard editingLinearID == nil, editingCropID == nil, activeTool == .selection,
              let bounds = selectionBounds else { return [:] }
        return Transform.handlePositions(for: bounds, rotationOffset: rotationOffset)
    }

    // MARK: Linear element editing

    /// Enter point-edit mode for the line/arrow hit at `point` (e.g. on a
    /// double-tap). Returns true if a linear element was found.
    @discardableResult
    public func beginLinearEdit(at point: Point) -> Bool {
        let threshold = handleHitRadius(.mouse)
        for element in scene.visibleElements.reversed()
            where !element.base.locked && linearPoints(of: element) != nil
            && HitTest.hit(element, at: point, threshold: threshold) {
            editingLinearID = element.id
            selectedIDs = [element.id]
            return true
        }
        return false
    }

    public func exitLinearEdit() {
        editingLinearID = nil
        elbowDrag = nil
    }

    /// Global point + midpoint positions for the line being edited, for the
    /// overlay. `nil` when not editing.
    public func linearEditHandles() -> (points: [Point], midpoints: [Point])? {
        guard let id = editingLinearID, let element = scene.element(id: id),
              let pts = linearPoints(of: element) else { return nil }
        let base = element.base
        let points = pts.map { Point(base.x + $0.x, base.y + $0.y) }
        var midpoints: [Point] = []
        if points.count >= 2 {
            for i in 0 ..< (points.count - 1) {
                midpoints.append(points[i].midpoint(to: points[i + 1]))
            }
        }
        return (points, midpoints)
    }

    private func handleLinearEditDown(_ event: PointerEvent) -> Bool {
        guard let id = editingLinearID, let element = scene.element(id: id),
              let pts = linearPoints(of: element) else {
            exitLinearEdit()
            return false
        }
        let base = element.base
        let threshold = handleHitRadius(event.type)

        // Elbow arrows are reshaped by dragging whole segments, not vertices.
        if case let .arrow(props) = element.kind, props.elbowed {
            for handle in elbowSegmentHandles(id)
                where handle.point.distance(to: event.scenePoint) <= threshold {
                elbowDrag = (id, handle.index)
                return true
            }
            exitLinearEdit()
            return false
        }

        for (i, point) in pts.enumerated() {
            let global = Point(base.x + point.x, base.y + point.y)
            if global.distance(to: event.scenePoint) <= threshold {
                interaction = .draggingLinearPoint(id: id, index: i)
                return true
            }
        }
        for i in 0 ..< max(0, pts.count - 1) {
            let a = Point(base.x + pts[i].x, base.y + pts[i].y)
            let b = Point(base.x + pts[i + 1].x, base.y + pts[i + 1].y)
            if a.midpoint(to: b).distance(to: event.scenePoint) <= threshold {
                var newPoints = pts
                newPoints.insert(Point(event.scenePoint.x - base.x, event.scenePoint.y - base.y), at: i + 1)
                store.modifyScene { $0.replace(setLinearPoints(newPoints, on: element)) }
                interaction = .draggingLinearPoint(id: id, index: i + 1)
                return true
            }
        }
        // Clicked away from any handle — leave edit mode and fall back to normal.
        exitLinearEdit()
        return false
    }

    private func moveLinearPoint(id: String, index: Int, to point: Point) {
        guard let element = scene.element(id: id), var pts = linearPoints(of: element),
              pts.indices.contains(index) else { return }
        pts[index] = Point(point.x - element.base.x, point.y - element.base.y)
        store.modifyScene { $0.replace(setLinearPoints(pts, on: element)) }
    }

    private func linearPoints(of element: ExcalidrawElement) -> [Point]? {
        switch element.kind {
        case let .line(props): props.points
        case let .arrow(props): props.points
        default: nil
        }
    }

    private func setLinearPoints(_ points: [Point], on element: ExcalidrawElement) -> ExcalidrawElement {
        var updated = element
        switch updated.kind {
        case var .line(props): props.points = points; updated.kind = .line(props)
        case var .arrow(props): props.points = points; updated.kind = .arrow(props)
        default: return element
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        updated.base.width = (xs.max() ?? 0) - (xs.min() ?? 0)
        updated.base.height = (ys.max() ?? 0) - (ys.min() ?? 0)
        return updated
    }

    // MARK: Pointer handling

    public func pointerDown(_ event: PointerEvent) {
        selectionRect = nil
        // Crop mode for an image takes priority.
        if editingCropID != nil, handleCropEditDown(event) { return }
        // Point-edit mode for a line/arrow takes priority.
        if editingLinearID != nil, handleLinearEditDown(event) { return }
        switch activeTool {
        case .eraser:
            interaction = .erasing(touched: [])
            eraseAt(event.scenePoint)
        case .hand:
            break // panning is handled by the UI layer (viewport)
        default:
            if let kind = activeTool.elementKind {
                beginCreating(kind: kind, at: event.scenePoint, pressure: event.pressure)
            } else {
                beginSelectionInteraction(event)
            }
        }
    }

    public func pointerMove(_ event: PointerEvent) {
        if cropDrag != nil { moveCropDrag(to: event.scenePoint); return }
        if let drag = elbowDrag {
            let newIndex = moveElbowSegment(id: drag.id, index: drag.index, to: event.scenePoint)
            elbowDrag = (drag.id, newIndex)
            return
        }
        switch interaction {
        case let .creating(id, origin, _):
            updateCreating(id: id, origin: origin, to: event.scenePoint)
            interaction = .creating(id: id, origin: origin, moved: true)
        case let .draggingLinearPoint(id, index):
            moveLinearPoint(id: id, index: index, to: event.scenePoint)
        case let .freehand(id, origin):
            appendFreehandPoint(id: id, origin: origin, point: event.scenePoint, pressure: event.pressure)
        case .erasing:
            eraseAt(event.scenePoint)
        case let .moving(origin, originals):
            var dx = event.scenePoint.x - origin.x
            var dy = event.scenePoint.y - origin.y
            if snapEnabled, !event.alt {
                applyObjectSnap(originals: originals, dx: &dx, dy: &dy)
            } else {
                snapLinesX = []; snapLinesY = []
            }
            store.modifyScene { scene in
                for (_, original) in originals {
                    scene.replace(Transform.translate(original, dx: dx, dy: dy))
                }
                if bindingEnabled { Self.updateBoundArrows(in: &scene, skipping: Set(originals.keys)) }
            }
        case let .boxSelecting(origin):
            selectionRect = Self.bbox(origin, event.scenePoint)
        case let .resizing(handle, bounds, originals):
            let newBounds = Transform.resize(
                bounds, handle: handle, to: event.scenePoint,
                keepAspect: event.shift, fromCenter: event.alt
            )
            store.modifyScene { scene in
                for (_, original) in originals {
                    scene.replace(Transform.scale(original, from: bounds, to: newBounds))
                }
                if bindingEnabled { Self.updateBoundArrows(in: &scene, skipping: Set(originals.keys)) }
            }
        case let .rotating(center, originals):
            let angle = Transform.rotationAngle(center: center, pointer: event.scenePoint, snap: event.shift)
            store.modifyScene { scene in
                for (_, original) in originals {
                    var e = original
                    e.base.angle = angle
                    scene.replace(e)
                }
            }
        case .idle:
            break
        }
    }

    public func pointerUp(_ event: PointerEvent) {
        if cropDrag != nil {
            cropDrag = nil
            store.commit()
            return
        }
        if elbowDrag != nil {
            elbowDrag = nil
            store.commit()
            return
        }
        switch interaction {
        case let .creating(id, _, moved):
            finishCreating(id: id, moved: moved)
        case let .freehand(id, _):
            finishFreehand(id: id)
        case .draggingLinearPoint:
            store.commit()
        case .erasing:
            store.commit()
            selectedIDs = []
        case let .moving(_, originals):
            snapLinesX = []; snapLinesY = []
            reassignFrameMembership(Set(originals.keys))
            store.commit()
        case .resizing, .rotating:
            snapLinesX = []; snapLinesY = []
            store.commit()
        case let .boxSelecting(origin):
            selectWithin(Self.bbox(origin, event.scenePoint), additive: event.toggleSelection)
            selectionRect = nil
        case .idle:
            break
        }
        interaction = .idle
    }

    // MARK: Commands

    /// Replace the document with a freshly loaded scene (resets history/selection).
    public func load(scene: Scene) {
        store = Store(scene: scene)
        selectedIDs = []
        interaction = .idle
    }

    public func setTool(_ tool: Tool) {
        activeTool = tool
        editingLinearID = nil
        exitCropEdit()
    }

    public func selectAll() {
        selectedIDs = Set(scene.visibleElements.map(\.id))
    }

    public func clearSelection() {
        selectedIDs = []
    }

    public func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        store.transaction { scene in
            for id in selectedIDs {
                scene.remove(id: id)
            }
        }
        selectedIDs = []
    }

    /// Apply a change to every selected element as one undo step (e.g. a style
    /// edit from the properties panel).
    public func updateSelected(_ change: (inout ExcalidrawElement) -> Void) {
        guard !selectedIDs.isEmpty else { return }
        store.transaction { scene in
            for id in selectedIDs {
                guard var element = scene.element(id: id) else { continue }
                change(&element)
                scene.replace(element)
            }
        }
    }

    @discardableResult public func undo() -> Bool {
        let ok = store.undo()
        pruneSelection()
        return ok
    }

    @discardableResult public func redo() -> Bool {
        let ok = store.redo()
        pruneSelection()
        return ok
    }

    // MARK: Interaction helpers

    private func beginCreating(kind: ElementKind, at origin: Point, pressure: Double) {
        let base = currentItem.makeBase(id: nextID(), seed: nextSeed(), x: origin.x, y: origin.y)
        var element: ExcalidrawElement
        switch kind {
        case .line:
            element = ExcalidrawElement(base: base, kind: .line(LinearProperties(points: [Point(0, 0), Point(0, 0)])))
        case .arrow:
            let props = ArrowProperties(
                points: [Point(0, 0), Point(0, 0)],
                startArrowhead: currentItem.startArrowhead,
                endArrowhead: currentItem.endArrowhead,
                elbowed: currentItem.elbowed
            )
            element = ExcalidrawElement(base: base, kind: .arrow(props))
        case .freedraw:
            let props = FreedrawProperties(points: [Point(0, 0)], pressures: [pressure], simulatePressure: false)
            element = ExcalidrawElement(base: base, kind: .freedraw(props))
            store.modifyScene { $0.add(element) }
            selectedIDs = [element.id]
            interaction = .freehand(id: element.id, origin: origin)
            return
        default:
            element = ExcalidrawElement(base: base, kind: kind)
        }
        // Rounded edges by default: splined lines/arrows, rounded rect/diamond.
        if currentItem.roundEdges, let type = Self.roundnessType(for: kind) {
            element.base.roundness = Roundness(type: type)
        }
        store.modifyScene { $0.add(element) }
        selectedIDs = [element.id]
        interaction = .creating(id: element.id, origin: origin, moved: false)
    }

    static func roundnessType(for kind: ElementKind) -> Int? {
        switch kind {
        case .line, .arrow: RoundnessType.proportionalRadius
        case .rectangle, .diamond: RoundnessType.adaptiveRadius
        default: nil
        }
    }

    private func appendFreehandPoint(id: String, origin: Point, point: Point, pressure: Double) {
        guard var element = scene.element(id: id), case var .freedraw(props) = element.kind else { return }
        props.points.append(Point(point.x - origin.x, point.y - origin.y))
        props.pressures.append(pressure)
        element.kind = .freedraw(props)
        let xs = props.points.map(\.x), ys = props.points.map(\.y)
        element.base.width = (xs.max() ?? 0) - (xs.min() ?? 0)
        element.base.height = (ys.max() ?? 0) - (ys.min() ?? 0)
        store.modifyScene { $0.replace(element) }
    }

    private func finishFreehand(id: String) {
        if let element = scene.element(id: id), case let .freedraw(props) = element.kind, props.points.count < 2 {
            // A single dab still counts as a stroke; keep it. Commit either way.
        }
        store.commit()
        if !toolLocked { activeTool = .selection }
    }

    /// Adjust a drag offset to snap the moving group to other elements,
    /// recording the matched guide lines.
    private func applyObjectSnap(originals: [String: ExcalidrawElement], dx: inout Double, dy: inout Double) {
        let moved = originals.values.map { Transform.translate($0, dx: dx, dy: dy) }
        guard let movingBounds = ElementGeometry.commonBounds(moved) else {
            snapLinesX = []; snapLinesY = []
            return
        }
        let movingIDs = Set(originals.keys)
        let statics = scene.visibleElements
            .filter { !movingIDs.contains($0.id) }
            .map { ElementGeometry.bounds($0) }
        let threshold = Snapping.defaultDistance / zoom
        let result = Snapping.snap(moving: movingBounds, statics: statics, threshold: threshold)
        var offsetX = result.offsetX, offsetY = result.offsetY
        var linesX = result.verticalLines, linesY = result.horizontalLines

        // Gap (distribution) snapping fills in an axis that edge/centre snapping
        // left unmatched, so equal spacing wins only when nothing else aligns.
        let gap = Snapping.gapSnap(moving: movingBounds, statics: statics, threshold: threshold)
        if linesX.isEmpty, !gap.verticalLines.isEmpty {
            offsetX = gap.offsetX; linesX = gap.verticalLines
        }
        if linesY.isEmpty, !gap.horizontalLines.isEmpty {
            offsetY = gap.offsetY; linesY = gap.horizontalLines
        }

        dx += offsetX
        dy += offsetY
        snapLinesX = linesX
        snapLinesY = linesY
    }

    private func eraseAt(_ point: Point) {
        let threshold = handleHitRadius(.mouse)
        let hits = scene.visibleElements.filter {
            !$0.base.locked && HitTest.hit($0, at: point, threshold: threshold)
        }
        guard !hits.isEmpty else { return }
        store.modifyScene { scene in
            for hit in hits {
                _ = scene.remove(id: hit.id)
            }
        }
    }

    private func updateCreating(id: String, origin: Point, to point: Point) {
        guard var element = scene.element(id: id) else { return }
        let endpoint = Point(point.x - origin.x, point.y - origin.y)
        if case var .line(props) = element.kind {
            element.base.x = origin.x
            element.base.y = origin.y
            element.base.width = abs(endpoint.x)
            element.base.height = abs(endpoint.y)
            props.points = [Point(0, 0), endpoint]
            element.kind = .line(props)
        } else if case var .arrow(props) = element.kind {
            element.base.x = origin.x
            element.base.y = origin.y
            element.base.width = abs(endpoint.x)
            element.base.height = abs(endpoint.y)
            props.points = [Point(0, 0), endpoint]
            element.kind = .arrow(props)
        } else {
            element.base.x = Swift.min(origin.x, point.x)
            element.base.y = Swift.min(origin.y, point.y)
            element.base.width = abs(point.x - origin.x)
            element.base.height = abs(point.y - origin.y)
        }
        store.modifyScene { $0.replace(element) }
    }

    private func finishCreating(id: String, moved: Bool) {
        let element = scene.element(id: id)
        let tiny = (element?.base.width ?? 0) < Transform.minSize && (element?.base.height ?? 0) < Transform.minSize
        if !moved || tiny {
            // A click without a drag creates nothing.
            store.modifyScene { scene in
                scene = Scene(
                    elements: scene.elements.filter { $0.id != id },
                    appState: scene.appState, files: scene.files
                )
            }
            selectedIDs = []
        } else {
            if bindingEnabled { bindArrowEndpoints(id) }
            routeElbowArrow(id)
            reassignFrameMembership([id])
            store.commit()
            if !toolLocked { activeTool = .selection }
        }
    }

    private func beginSelectionInteraction(_ event: PointerEvent) {
        let point = event.scenePoint
        // Handles take priority when something is selected.
        if let bounds = selectionBounds {
            for (handle, position) in Transform.handlePositions(for: bounds, rotationOffset: rotationOffset)
                where position.distance(to: point) <= handleHitRadius(event.type) {
                let originals = snapshotSelected()
                interaction = handle == .rotation
                    ? .rotating(
                        center: Point((bounds.minX + bounds.maxX) / 2, (bounds.minY + bounds.maxY) / 2),
                        originals: originals
                    )
                    : .resizing(handle: handle, bounds: bounds, originals: originals)
                return
            }
        }

        if let hit = topElement(at: point, type: event.type) {
            // Hitting one element of a group selects the whole group.
            let group = groupSiblings(of: hit)
            if event.toggleSelection {
                if selectedIDs.isSuperset(of: group) {
                    selectedIDs.subtract(group)
                } else {
                    selectedIDs.formUnion(group)
                }
            } else if !selectedIDs.contains(hit) {
                selectedIDs = group
            }
            interaction = .moving(origin: point, originals: snapshotForMove())
        } else {
            if !event.toggleSelection { selectedIDs = [] }
            interaction = .boxSelecting(origin: point)
            selectionRect = BoundingBox(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y)
        }
    }

    private func snapshotSelected() -> [String: ExcalidrawElement] {
        Dictionary(selectedElements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Snapshot for a move: the selection plus the children of any selected
    /// frames (so moving a frame moves its contents).
    private func snapshotForMove() -> [String: ExcalidrawElement] {
        var result = snapshotSelected()
        for element in selectedElements where Frames.isFrame(element) {
            for child in Frames.children(ofFrame: element.id, in: scene.visibleElements) {
                result[child.id] = child
            }
        }
        return result
    }

    /// Recompute `frameId` for the given non-frame elements based on which frame
    /// now contains them.
    private func reassignFrameMembership(_ ids: Set<String>) {
        store.modifyScene { scene in
            for id in ids {
                guard let element = scene.element(id: id), !Frames.isFrame(element) else { continue }
                let frameID = Frames.frame(containing: element, in: scene.visibleElements)
                if element.base.frameId != frameID {
                    var updated = element
                    updated.base.frameId = frameID
                    scene.replace(updated)
                }
            }
        }
    }

    private func topElement(at point: Point, type: PointerType) -> String? {
        let threshold = handleHitRadius(type)
        for element in scene.visibleElements.reversed()
            where !element.base.locked && HitTest.hit(element, at: point, threshold: threshold) {
            return element.id
        }
        return nil
    }

    private func selectWithin(_ rect: BoundingBox, additive: Bool) {
        let within = scene.visibleElements.filter { element in
            let b = ElementGeometry.bounds(element)
            return b.minX >= rect.minX && b.maxX <= rect.maxX && b.minY >= rect.minY && b.maxY <= rect.maxY
        }.flatMap { groupSiblings(of: $0.id) }
        if additive { selectedIDs.formUnion(within) } else { selectedIDs = Set(within) }
    }

    /// All visible elements sharing the (outermost) group of `id`, or just `id`
    /// if it isn't grouped — so selecting one groups them all.
    func groupSiblings(of id: String) -> Set<String> {
        guard let element = scene.element(id: id), let group = element.base.groupIds.last else { return [id] }
        let siblings = scene.visibleElements.filter { $0.base.groupIds.contains(group) }.map(\.id)
        return Set(siblings).union([id])
    }

    private func pruneSelection() {
        let live = Set(scene.visibleElements.map(\.id))
        selectedIDs.formIntersection(live)
    }

    func handleHitRadius(_ type: PointerType) -> Double {
        let px: Double = switch type {
        case .touch: 28
        case .pen: 16
        case .mouse: 10
        }
        return px / zoom
    }

    private var rotationOffset: Double {
        30 / zoom
    }

    /// Normalized bounding box of two corner points.
    private static func bbox(_ a: Point, _ b: Point) -> BoundingBox {
        BoundingBox(
            minX: Swift.min(a.x, b.x), minY: Swift.min(a.y, b.y),
            maxX: Swift.max(a.x, b.x), maxY: Swift.max(a.y, b.y)
        )
    }
}
