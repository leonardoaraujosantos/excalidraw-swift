import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Elbow-arrow routing: recompute an orthogonal path for an arrow whose
/// `elbowed` flag is set, from its global endpoints and any bound shapes.
public extension EditorController {
    /// Set the elbow mode for newly created arrows and convert any selected
    /// arrows to/from elbow, re-routing as one undo step.
    func setElbowed(_ elbowed: Bool) {
        currentItem.elbowed = elbowed
        let arrowIDs = selectedElements.compactMap { element -> String? in
            if case .arrow = element.kind { return element.id }
            return nil
        }
        guard !arrowIDs.isEmpty else { return }
        store.transaction { scene in
            for id in arrowIDs {
                guard var arrow = scene.element(id: id), case var .arrow(props) = arrow.kind,
                      props.elbowed != elbowed, let first = props.points.first,
                      let last = props.points.last else { continue }
                props.elbowed = elbowed
                arrow.kind = .arrow(props)
                if elbowed {
                    let startGlobal = Point(arrow.base.x + first.x, arrow.base.y + first.y)
                    let endGlobal = Point(arrow.base.x + last.x, arrow.base.y + last.y)
                    Self.applyElbowRoute(to: &arrow, startGlobal: startGlobal, endGlobal: endGlobal, in: scene)
                }
                scene.replace(arrow)
            }
        }
    }

    /// Global midpoints of the draggable interior segments of the elbow arrow
    /// `id`, for the edit overlay. Empty for non-elbow arrows.
    func elbowSegmentHandles(_ id: String) -> [(index: Int, point: Point)] {
        guard let element = scene.element(id: id), case let .arrow(props) = element.kind, props.elbowed else {
            return []
        }
        let global = props.points.map { Point(element.base.x + $0.x, element.base.y + $0.y) }
        return ElbowArrow.fixableSegments(global).map { ($0.index, $0.midpoint) }
    }

    /// Drag the interior segment `index` of elbow arrow `id` so it passes
    /// through the global point `to`, pinning it as a fixed segment.
    func moveElbowSegment(id: String, index: Int, to point: Point) {
        store.modifyScene { scene in
            guard var arrow = scene.element(id: id), case var .arrow(props) = arrow.kind, props.elbowed else { return }
            let global = props.points.map { Point(arrow.base.x + $0.x, arrow.base.y + $0.y) }
            let moved = ElbowArrow.moveSegment(global, index: index, to: point)
            let origin = moved.first ?? point
            props.points = moved.map { Point($0.x - origin.x, $0.y - origin.y) }
            arrow.base.x = origin.x
            arrow.base.y = origin.y
            let xs = props.points.map(\.x), ys = props.points.map(\.y)
            arrow.base.width = (xs.max() ?? 0) - (xs.min() ?? 0)
            arrow.base.height = (ys.max() ?? 0) - (ys.min() ?? 0)

            // Record / update the pinned segment.
            guard props.points.indices.contains(index) else { arrow.kind = .arrow(props); scene.replace(arrow); return }
            let pinned = FixedSegment(start: props.points[index - 1], end: props.points[index], index: index)
            var segments = props.fixedSegments ?? []
            if let existing = segments.firstIndex(where: { $0.index == index }) {
                segments[existing] = pinned
            } else {
                segments.append(pinned)
                segments.sort { $0.index < $1.index }
            }
            props.fixedSegments = segments
            arrow.kind = .arrow(props)
            scene.replace(arrow)
        }
    }

    /// Re-route the elbow arrow `id` from its current endpoints (called after
    /// creation and whenever an endpoint moves).
    func routeElbowArrow(_ id: String) {
        store.modifyScene { scene in
            guard var arrow = scene.element(id: id), case let .arrow(props) = arrow.kind, props.elbowed,
                  let first = props.points.first, let last = props.points.last else { return }
            let startGlobal = Point(arrow.base.x + first.x, arrow.base.y + first.y)
            let endGlobal = Point(arrow.base.x + last.x, arrow.base.y + last.y)
            Self.applyElbowRoute(to: &arrow, startGlobal: startGlobal, endGlobal: endGlobal, in: scene)
            scene.replace(arrow)
        }
    }

    /// Rewrite `arrow`'s points as the elbow route between two global endpoints,
    /// reanchoring its origin/size. No-op for non-elbow arrows. Shared by
    /// creation and the bound-arrow update pass.
    internal static func applyElbowRoute(
        to arrow: inout ExcalidrawElement, startGlobal: Point, endGlobal: Point, in scene: Scene
    ) {
        guard case var .arrow(props) = arrow.kind, props.elbowed else { return }
        let routed: [Point]
        if let fixed = props.fixedSegments, !fixed.isEmpty, props.points.count >= 4 {
            // Preserve the manually pinned segments: only stretch the first and
            // last segments to follow the moved endpoints.
            let global = props.points.map { Point(arrow.base.x + $0.x, arrow.base.y + $0.y) }
            routed = ElbowArrow.followEndpoints(global, newStart: startGlobal, newEnd: endGlobal)
        } else {
            let startBox = props.startBinding
                .flatMap { scene.element(id: $0.elementId) }.map { ElementGeometry.bounds($0) }
            let endBox = props.endBinding
                .flatMap { scene.element(id: $0.elementId) }.map { ElementGeometry.bounds($0) }
            routed = ElbowArrow.route(start: startGlobal, startBox: startBox, end: endGlobal, endBox: endBox)
        }
        let origin = routed.first ?? startGlobal
        props.points = routed.map { Point($0.x - origin.x, $0.y - origin.y) }
        // Refresh pinned-segment coordinates against the re-anchored points.
        if let fixed = props.fixedSegments, !fixed.isEmpty {
            props.fixedSegments = fixed.compactMap { segment in
                guard props.points.indices.contains(segment.index) else { return nil }
                return FixedSegment(
                    start: props.points[segment.index - 1], end: props.points[segment.index], index: segment.index
                )
            }
        }
        arrow.base.x = origin.x
        arrow.base.y = origin.y
        let xs = props.points.map(\.x), ys = props.points.map(\.y)
        arrow.base.width = (xs.max() ?? 0) - (xs.min() ?? 0)
        arrow.base.height = (ys.max() ?? 0) - (ys.min() ?? 0)
        arrow.kind = .arrow(props)
    }
}
