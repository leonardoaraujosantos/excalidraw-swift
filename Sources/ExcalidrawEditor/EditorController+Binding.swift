import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Arrow↔shape binding: attach an arrow's endpoints to nearby bindable shapes
/// on creation, and follow those shapes when they move/resize.
extension EditorController {
    /// If the element is an arrow, bind its endpoints to nearby bindable shapes.
    func bindArrowEndpoints(_ id: String) {
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
            if props.elbowed {
                applyElbowRoute(to: &arrow, startGlobal: startGlobal, endGlobal: endGlobal, in: scene)
            } else {
                arrow.base.x = startGlobal.x
                arrow.base.y = startGlobal.y
                props.points = [Point(0, 0), Point(endGlobal.x - startGlobal.x, endGlobal.y - startGlobal.y)]
                arrow.base.width = abs(endGlobal.x - startGlobal.x)
                arrow.base.height = abs(endGlobal.y - startGlobal.y)
                arrow.kind = .arrow(props)
            }
            scene.replace(arrow)
        }
    }
}
