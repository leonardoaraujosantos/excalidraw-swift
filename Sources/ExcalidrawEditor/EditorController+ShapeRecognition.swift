import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Freehand shape recognition: replace a freedraw stroke with the clean shape
/// it resembles (rectangle, ellipse, diamond, triangle, or line).
public extension EditorController {
    /// If `id` is a freedraw stroke that resembles a known shape, replace it
    /// with that shape (preserving style) as one undo step and keep it selected.
    /// Returns the recognized shape, or `nil` if nothing matched.
    @discardableResult
    func recognizeFreedraw(_ id: String) -> RecognizedShape? {
        guard let element = scene.element(id: id), case let .freedraw(props) = element.kind else { return nil }
        let global = props.points.map { Point(element.base.x + $0.x, element.base.y + $0.y) }
        guard let recognition = ShapeRecognizer.recognize(global) else { return nil }

        var replacement = element
        applyRecognition(recognition, to: &replacement)
        store.transaction { $0.replace(replacement) }
        selectedIDs = [id]
        return recognition.shape
    }

    private func applyRecognition(_ recognition: ShapeRecognition, to element: inout ExcalidrawElement) {
        let box = recognition.bounds
        switch recognition.shape {
        case .rectangle, .ellipse, .diamond:
            element.base.x = box.minX
            element.base.y = box.minY
            element.base.width = box.width
            element.base.height = box.height
            element.kind = switch recognition.shape {
            case .ellipse: .ellipse
            case .diamond: .diamond
            default: .rectangle
            }
        case .line:
            setPolyline(recognition.vertices, polygon: false, on: &element)
        case .triangle:
            // A closed 3-point polygon (start repeated to close it).
            setPolyline(recognition.vertices + [recognition.vertices.first ?? .zero], polygon: true, on: &element)
        }
    }

    private func setPolyline(_ vertices: [Point], polygon: Bool, on element: inout ExcalidrawElement) {
        let origin = vertices.first ?? .zero
        let local = vertices.map { Point($0.x - origin.x, $0.y - origin.y) }
        element.base.x = origin.x
        element.base.y = origin.y
        let xs = local.map(\.x), ys = local.map(\.y)
        element.base.width = (xs.max() ?? 0) - (xs.min() ?? 0)
        element.base.height = (ys.max() ?? 0) - (ys.min() ?? 0)
        element.kind = .line(LinearProperties(points: local, polygon: polygon))
    }
}
