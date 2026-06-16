import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Direction in which a flowchart node is spawned from its source.
public enum FlowchartDirection: Sendable {
    case up, down, left, right

    var heading: Heading {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }
}

/// Flowchart helpers: spawn a new node linked to the selected one by a bound
/// elbow arrow (`packages/element/src/flowchart.ts`).
public extension EditorController {
    /// Gap between a flowchart node and the node it spawns.
    private static var flowchartGap: Double {
        100
    }

    /// Create a new node of the same shape/size/style as `id`, offset in
    /// `direction`, connected by a bound elbow arrow, and select it. Returns the
    /// new node and arrow ids, or `nil` if `id` isn't a bindable node.
    @discardableResult
    func addFlowchartNode(from id: String, direction: FlowchartDirection) -> (node: String, arrow: String)? {
        guard let source = scene.element(id: id), Binding.isBindable(source), !isLinear(source) else { return nil }
        let base = source.base
        let gap = Self.flowchartGap
        let offset: (x: Double, y: Double) = switch direction {
        case .right: (base.width + gap, 0)
        case .left: (-(base.width + gap), 0)
        case .down: (0, base.height + gap)
        case .up: (0, -(base.height + gap))
        }
        // Stagger when nodes already occupy the slot directly in that direction.
        let stagger = flowchartStagger(from: source, direction: direction)

        var nodeBase = base
        let nodeID = nextID()
        nodeBase.id = nodeID
        nodeBase.seed = nextSeed()
        nodeBase.x = base.x + offset.x + stagger.x
        nodeBase.y = base.y + offset.y + stagger.y
        nodeBase.boundElements = nil
        nodeBase.groupIds = []
        let newNode = ExcalidrawElement(base: nodeBase, kind: source.kind)

        let arrowID = nextID()
        let arrow = makeBindingArrow(id: arrowID, from: source, to: newNode, direction: direction)

        store.transaction { scene in
            scene.add(newNode)
            scene.add(arrow)
            Self.registerBoundArrow(arrowID, on: id, in: &scene)
            Self.registerBoundArrow(arrowID, on: nodeID, in: &scene)
            // Route the elbow arrow within the same undo step.
            if var routed = scene.element(id: arrowID), case let .arrow(p) = routed.kind,
               let first = p.points.first, let last = p.points.last {
                let startGlobal = Point(routed.base.x + first.x, routed.base.y + first.y)
                let endGlobal = Point(routed.base.x + last.x, routed.base.y + last.y)
                Self.applyElbowRoute(to: &routed, startGlobal: startGlobal, endGlobal: endGlobal, in: scene)
                scene.replace(routed)
            }
        }
        selectedIDs = [nodeID]
        return (nodeID, arrowID)
    }

    private func isLinear(_ element: ExcalidrawElement) -> Bool {
        switch element.kind {
        case .arrow, .line, .freedraw: true
        default: false
        }
    }

    /// Perpendicular offset so repeated spawns in the same direction fan out
    /// instead of stacking, based on how many nodes already sit in that slot.
    private func flowchartStagger(
        from source: ExcalidrawElement,
        direction: FlowchartDirection
    ) -> (x: Double, y: Double) {
        let count = linkedNodeCount(from: source, direction: direction)
        guard count > 0 else { return (0, 0) }
        let base = source.base
        // Alternate sides: 1 → +, 2 → -, 3 → ++, ...
        let step = (count + 1) / 2
        let sign: Double = count.isMultiple(of: 2) ? -1 : 1
        let amount = Double(step) * sign
        switch direction {
        case .up, .down: return ((base.width + Self.flowchartGap) * amount, 0)
        case .left, .right: return (0, (base.height + Self.flowchartGap) * amount)
        }
    }

    /// Count arrows already leaving `source` whose heading matches `direction`.
    private func linkedNodeCount(from source: ExcalidrawElement, direction: FlowchartDirection) -> Int {
        let bound = source.base.boundElements ?? []
        let arrowIDs = Set(bound.filter { $0.type == .arrow }.map(\.id))
        let box = ElementGeometry.bounds(source)
        return scene.visibleElements.count(where: { element in
            guard arrowIDs.contains(element.id), case let .arrow(props) = element.kind,
                  let first = props.points.first, let last = props.points.last else { return false }
            // Use whichever endpoint leaves the source.
            let start = Point(element.base.x + first.x, element.base.y + first.y)
            let end = Point(element.base.x + last.x, element.base.y + last.y)
            let outward = box.contains(start) ? end : start
            return Heading.from(box: box, toward: outward) == direction.heading
        })
    }

    private func makeBindingArrow(
        id: String, from source: ExcalidrawElement, to target: ExcalidrawElement, direction: FlowchartDirection
    ) -> ExcalidrawElement {
        let sBox = ElementGeometry.bounds(source)
        let tBox = ElementGeometry.bounds(target)
        let start = edgePoint(of: sBox, heading: direction.heading)
        let end = edgePoint(of: tBox, heading: direction.heading.flipped())
        var base = source.base
        base.id = id
        base.seed = nextSeed()
        base.x = start.x
        base.y = start.y
        base.width = abs(end.x - start.x)
        base.height = abs(end.y - start.y)
        base.backgroundColor = "transparent"
        base.boundElements = nil
        base.groupIds = []
        let props = ArrowProperties(
            points: [Point(0, 0), Point(end.x - start.x, end.y - start.y)],
            startBinding: FixedPointBinding(
                elementId: source.id, fixedPoint: Binding.fixedPoint(for: start, in: sBox), mode: .orbit
            ),
            endBinding: FixedPointBinding(
                elementId: target.id, fixedPoint: Binding.fixedPoint(for: end, in: tBox), mode: .orbit
            ),
            endArrowhead: .arrow, elbowed: true
        )
        return ExcalidrawElement(base: base, kind: .arrow(props))
    }

    private func edgePoint(of box: BoundingBox, heading: Heading) -> Point {
        let midX = (box.minX + box.maxX) / 2
        let midY = (box.minY + box.maxY) / 2
        switch heading {
        case .up: return Point(midX, box.minY)
        case .down: return Point(midX, box.maxY)
        case .left: return Point(box.minX, midY)
        case .right: return Point(box.maxX, midY)
        }
    }

    private static func registerBoundArrow(_ arrowID: String, on targetID: String, in scene: inout Scene) {
        guard var target = scene.element(id: targetID) else { return }
        var bound = target.base.boundElements ?? []
        guard !bound.contains(where: { $0.id == arrowID }) else { return }
        bound.append(BoundElement(id: arrowID, type: .arrow))
        target.base.boundElements = bound
        scene.replace(target)
    }
}
