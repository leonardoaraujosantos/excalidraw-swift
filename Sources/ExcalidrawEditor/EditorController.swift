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

    let nextID: () -> String
    let nextSeed: () -> Int

    private enum Interaction {
        case idle
        case creating(id: String, origin: Point, moved: Bool)
        case freehand(id: String, origin: Point)
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
    /// selection tool is active.
    public func transformHandles() -> [TransformHandle: Point] {
        guard activeTool == .selection, let bounds = selectionBounds else { return [:] }
        return Transform.handlePositions(for: bounds, rotationOffset: rotationOffset)
    }

    // MARK: Pointer handling

    public func pointerDown(_ event: PointerEvent) {
        selectionRect = nil
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
        switch interaction {
        case let .creating(id, origin, _):
            updateCreating(id: id, origin: origin, to: event.scenePoint)
            interaction = .creating(id: id, origin: origin, moved: true)
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
        switch interaction {
        case let .creating(id, _, moved):
            finishCreating(id: id, moved: moved)
        case let .freehand(id, _):
            finishFreehand(id: id)
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
        let element: ExcalidrawElement
        switch kind {
        case .line:
            element = ExcalidrawElement(base: base, kind: .line(LinearProperties(points: [Point(0, 0), Point(0, 0)])))
        case .arrow:
            // Arrows default to an arrowhead on the end.
            let props = ArrowProperties(points: [Point(0, 0), Point(0, 0)], endArrowhead: .arrow)
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
        store.modifyScene { $0.add(element) }
        selectedIDs = [element.id]
        interaction = .creating(id: element.id, origin: origin, moved: false)
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
        let result = Snapping.snap(moving: movingBounds, statics: statics, threshold: Snapping.defaultDistance / zoom)
        dx += result.offsetX
        dy += result.offsetY
        snapLinesX = result.verticalLines
        snapLinesY = result.horizontalLines
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
            reassignFrameMembership([id])
            store.commit()
            if !toolLocked { activeTool = .selection }
        }
    }

    /// If the element is an arrow, bind its endpoints to nearby bindable shapes.
    private func bindArrowEndpoints(_ id: String) {
        store.modifyScene { scene in
            guard var arrow = scene.element(id: id),
                  case var .arrow(props) = arrow.kind,
                  let first = props.points.first, let last = props.points.last else { return }
            let startGlobal = Point(arrow.base.x + first.x, arrow.base.y + first.y)
            let endGlobal = Point(arrow.base.x + last.x, arrow.base.y + last.y)
            let others = scene.visibleElements

            if let target = Binding.bindableElement(at: startGlobal, in: others, excluding: [id]) {
                let bounds = ElementGeometry.bounds(target)
                props.startBinding = FixedPointBinding(
                    elementId: target.id, fixedPoint: Binding.fixedPoint(for: startGlobal, in: bounds), mode: .orbit
                )
                Self.addBoundArrow(arrowID: id, to: target.id, in: &scene)
            }
            if let target = Binding.bindableElement(at: endGlobal, in: others, excluding: [id]) {
                let bounds = ElementGeometry.bounds(target)
                props.endBinding = FixedPointBinding(
                    elementId: target.id, fixedPoint: Binding.fixedPoint(for: endGlobal, in: bounds), mode: .orbit
                )
                Self.addBoundArrow(arrowID: id, to: target.id, in: &scene)
            }
            arrow.kind = .arrow(props)
            scene.replace(arrow)
        }
    }

    private static func addBoundArrow(arrowID: String, to targetID: String, in scene: inout Scene) {
        guard var target = scene.element(id: targetID) else { return }
        var bound = target.base.boundElements ?? []
        guard !bound.contains(where: { $0.id == arrowID }) else { return }
        bound.append(BoundElement(id: arrowID, type: .arrow))
        target.base.boundElements = bound
        scene.replace(target)
    }

    /// Recompute the endpoints of bound arrows from their targets' current
    /// bounds, skipping arrows that are themselves being dragged.
    static func updateBoundArrows(in scene: inout Scene, skipping: Set<String>) {
        for element in scene.elements where !element.base.isDeleted && !skipping.contains(element.id) {
            guard case var .arrow(props) = element.kind,
                  let first = props.points.first, let last = props.points.last,
                  props.startBinding != nil || props.endBinding != nil else { continue }
            var startGlobal = Point(element.base.x + first.x, element.base.y + first.y)
            var endGlobal = Point(element.base.x + last.x, element.base.y + last.y)
            if let binding = props.startBinding, let target = scene.element(id: binding.elementId) {
                startGlobal = Binding.point(forFixedPoint: binding.fixedPoint, in: ElementGeometry.bounds(target))
            }
            if let binding = props.endBinding, let target = scene.element(id: binding.elementId) {
                endGlobal = Binding.point(forFixedPoint: binding.fixedPoint, in: ElementGeometry.bounds(target))
            }
            var arrow = element
            arrow.base.x = startGlobal.x
            arrow.base.y = startGlobal.y
            props.points = [Point(0, 0), Point(endGlobal.x - startGlobal.x, endGlobal.y - startGlobal.y)]
            arrow.base.width = abs(endGlobal.x - startGlobal.x)
            arrow.base.height = abs(endGlobal.y - startGlobal.y)
            arrow.kind = .arrow(props)
            scene.replace(arrow)
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
            if event.toggleSelection {
                if selectedIDs.contains(hit) { selectedIDs.remove(hit) } else { selectedIDs.insert(hit) }
            } else if !selectedIDs.contains(hit) {
                selectedIDs = [hit]
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
        }.map(\.id)
        if additive { selectedIDs.formUnion(within) } else { selectedIDs = Set(within) }
    }

    private func pruneSelection() {
        let live = Set(scene.visibleElements.map(\.id))
        selectedIDs.formIntersection(live)
    }

    private func handleHitRadius(_ type: PointerType) -> Double {
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

    // MARK: Actions (group / duplicate / align / flip / z-order / lock)

    /// Group the selected elements by appending a new shared group id.
    public func group() {
        guard selectedIDs.count > 1 else { return }
        let groupID = nextID()
        updateSelected { $0.base.groupIds.append(groupID) }
    }

    /// Ungroup: drop the outermost (last) group id from each selected element.
    public func ungroup() {
        updateSelected { if !$0.base.groupIds.isEmpty { $0.base.groupIds.removeLast() } }
    }

    /// Duplicate the selection, offset by (10, 10), and select the copies.
    public func duplicate() {
        let originals = selectedElements
        guard !originals.isEmpty else { return }
        var newIDs: [String] = []
        store.transaction { scene in
            for original in originals {
                var copy = original
                copy.base.id = nextID()
                copy.base.x += 10
                copy.base.y += 10
                scene.add(copy)
                newIDs.append(copy.id)
            }
        }
        selectedIDs = Set(newIDs)
    }

    public func setLocked(_ locked: Bool) {
        updateSelected { $0.base.locked = locked }
    }

    // MARK: Z-order

    public enum ZOrder { case front, back, forward, backward }

    public func reorder(_ order: ZOrder) {
        guard !selectedIDs.isEmpty else { return }
        store.transaction { scene in
            var elements = scene.elements
            let selected = selectedIDs
            switch order {
            case .front:
                let moving = elements.filter { selected.contains($0.id) }
                elements.removeAll { selected.contains($0.id) }
                elements.append(contentsOf: moving)
            case .back:
                let moving = elements.filter { selected.contains($0.id) }
                elements.removeAll { selected.contains($0.id) }
                elements.insert(contentsOf: moving, at: 0)
            case .forward:
                for i in stride(from: elements.count - 2, through: 0, by: -1)
                    where selected.contains(elements[i].id) && !selected.contains(elements[i + 1].id) {
                    elements.swapAt(i, i + 1)
                }
            case .backward:
                for i in 1 ..< elements.count
                    where selected.contains(elements[i].id) && !selected.contains(elements[i - 1].id) {
                    elements.swapAt(i, i - 1)
                }
            }
            scene.replaceAll(elements)
        }
    }

    // MARK: Align / distribute / flip

    public enum Alignment { case left, centerX, right, top, centerY, bottom }

    public func align(_ alignment: Alignment) {
        guard selectedElements.count > 1, let group = selectionBounds else { return }
        updateSelected { element in
            let b = ElementGeometry.bounds(element)
            switch alignment {
            case .left: element.base.x += group.minX - b.minX
            case .right: element.base.x += group.maxX - b.maxX
            case .centerX: element.base.x += (group.minX + group.maxX) / 2 - (b.minX + b.maxX) / 2
            case .top: element.base.y += group.minY - b.minY
            case .bottom: element.base.y += group.maxY - b.maxY
            case .centerY: element.base.y += (group.minY + group.maxY) / 2 - (b.minY + b.maxY) / 2
            }
        }
    }

    public func flip(horizontal: Bool) {
        guard let bounds = selectionBounds else { return }
        updateSelected { element in
            let b = ElementGeometry.bounds(element)
            // Mirror the element's position across the selection bounds.
            if horizontal {
                element.base.x = bounds.minX + bounds.maxX - b.maxX
            } else {
                element.base.y = bounds.minY + bounds.maxY - b.maxY
            }
            Self.flipPoints(&element, horizontal: horizontal)
        }
    }

    private static func flipPoints(_ element: inout ExcalidrawElement, horizontal: Bool) {
        func mirror(_ pts: [Point]) -> [Point] {
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let maxX = xs.max() ?? 0, maxY = ys.max() ?? 0
            return pts.map { Point(horizontal ? maxX - $0.x : $0.x, horizontal ? $0.y : maxY - $0.y) }
        }
        switch element.kind {
        case var .line(p): p.points = mirror(p.points); element.kind = .line(p)
        case var .arrow(p): p.points = mirror(p.points); element.kind = .arrow(p)
        case var .freedraw(p): p.points = mirror(p.points); element.kind = .freedraw(p)
        default: break
        }
    }
}
