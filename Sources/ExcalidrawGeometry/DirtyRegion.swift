import ExcalidrawModel
import Foundation

/// Computes the region of the scene that changed between two revisions — the
/// union of the bounds of every added, removed, or modified element. This is
/// the basis for incremental redraw: a renderer can clip to this region instead
/// of repainting the whole canvas.
public enum DirtyRegion {
    /// The bounding box enclosing every element that was added, removed, or
    /// changed between `old` and `new`. Returns `nil` when nothing changed.
    public static func changed(from old: [ExcalidrawElement], to new: [ExcalidrawElement]) -> BoundingBox? {
        var oldByID: [String: ExcalidrawElement] = [:]
        for element in old {
            oldByID[element.id] = element
        }
        var newByID: [String: ExcalidrawElement] = [:]
        for element in new {
            newByID[element.id] = element
        }

        var region: BoundingBox?
        func accumulate(_ box: BoundingBox) {
            region = region.map { $0.union(box) } ?? box
        }

        for element in new {
            if let previous = oldByID[element.id] {
                if previous != element {
                    accumulate(ElementGeometry.bounds(previous))
                    accumulate(ElementGeometry.bounds(element))
                }
            } else {
                accumulate(ElementGeometry.bounds(element)) // added
            }
        }
        for element in old where newByID[element.id] == nil {
            accumulate(ElementGeometry.bounds(element)) // removed
        }
        return region
    }
}
