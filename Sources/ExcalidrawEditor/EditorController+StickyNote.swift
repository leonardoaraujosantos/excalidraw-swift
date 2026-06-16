import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

public extension EditorController {
    /// Default sticky-note fill (Excalidraw's note yellow).
    static var stickyNoteColor: String {
        "#ffec99"
    }

    /// Default sticky-note edge length.
    private static var stickyNoteSize: Double {
        160
    }

    /// Create a sticky note (a filled, rounded square) with a centered, bound
    /// text element, grouped so they move and select together. Returns the
    /// container and text ids; the UI begins editing the text.
    @discardableResult
    func createStickyNote(at point: Point, color: String? = nil) -> (container: String, text: String) {
        let size = Self.stickyNoteSize
        let groupID = nextID()
        let containerID = nextID()
        let textID = nextID()

        var containerBase = currentItem.makeBase(id: containerID, seed: nextSeed(), x: point.x, y: point.y)
        containerBase.width = size
        containerBase.height = size
        containerBase.backgroundColor = color ?? Self.stickyNoteColor
        containerBase.fillStyle = .solid
        containerBase.roundness = Roundness(type: RoundnessType.adaptiveRadius)
        containerBase.groupIds = [groupID]
        containerBase.boundElements = [BoundElement(id: textID, type: .text)]
        let container = ExcalidrawElement(base: containerBase, kind: .rectangle)

        var textBase = currentItem.makeBase(id: textID, seed: nextSeed(), x: point.x, y: point.y + size / 2)
        textBase.groupIds = [groupID]
        textBase.backgroundColor = "transparent"
        let textProps = TextProperties(
            fontSize: currentItem.fontSize, fontFamily: currentItem.fontFamily,
            text: "", textAlign: .center, verticalAlign: .middle, containerId: containerID, autoResize: false
        )
        let text = ExcalidrawElement(base: textBase, kind: .text(textProps))

        store.modifyScene { scene in
            scene.add(container)
            scene.add(text)
        }
        selectedIDs = [containerID]
        return (containerID, textID)
    }

    /// The text element bound to container `id`, if any (for editing a note).
    func boundTextID(of id: String) -> String? {
        guard let element = scene.element(id: id) else { return nil }
        return element.base.boundElements?.first { $0.type == .text }?.id
    }

    /// The topmost container with bound text hit at `point` (so a tap/double-tap
    /// can edit a sticky note's label). Selects the container.
    func boundTextHit(at point: Point) -> (container: String, text: String)? {
        let threshold = handleHitRadius(.mouse)
        for element in scene.visibleElements.reversed()
            where !element.base.locked && HitTest.hit(element, at: point, threshold: threshold) {
            if let textID = boundTextID(of: element.id) {
                selectedIDs = [element.id]
                return (element.id, textID)
            }
        }
        return nil
    }
}
