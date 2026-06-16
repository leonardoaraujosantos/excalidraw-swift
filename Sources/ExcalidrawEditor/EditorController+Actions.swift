import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Selection actions: grouping, duplication, locking, z-order, alignment, and
/// flipping. Split out of `EditorController` to keep that type focused on the
/// pointer state machine. These operate via the public/internal API and never
/// touch the private interaction state.
public extension EditorController {
    // MARK: Actions (group / duplicate / align / flip / z-order / lock)

    /// Group the selected elements by appending a new shared group id.
    func group() {
        guard selectedIDs.count > 1 else { return }
        let groupID = nextID()
        updateSelected { $0.base.groupIds.append(groupID) }
    }

    /// Ungroup: drop the outermost (last) group id from each selected element.
    func ungroup() {
        updateSelected { if !$0.base.groupIds.isEmpty { $0.base.groupIds.removeLast() } }
    }

    /// Duplicate the selection, offset by (10, 10), and select the copies.
    func duplicate() {
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

    func setLocked(_ locked: Bool) {
        updateSelected { $0.base.locked = locked }
    }

    // MARK: Z-order

    enum ZOrder { case front, back, forward, backward }

    func reorder(_ order: ZOrder) {
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

    enum Alignment { case left, centerX, right, top, centerY, bottom }

    func align(_ alignment: Alignment) {
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

    func flip(horizontal: Bool) {
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
