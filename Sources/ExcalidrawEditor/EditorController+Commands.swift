import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Content-creation commands: clipboard, text, image, and library insertion.
/// Split out of `EditorController` to keep that type focused on the pointer
/// state machine.
public extension EditorController {
    // MARK: Image crop

    /// Set (or clear, with `nil`) the crop rectangle on an image element, as one
    /// undo step. The crop is in natural-image pixel coordinates.
    func setCrop(id: String, _ crop: ImageCrop?) {
        guard let element = scene.element(id: id), case var .image(props) = element.kind else { return }
        store.transaction { scene in
            var updated = element
            props.crop = crop
            updated.kind = .image(props)
            scene.replace(updated)
        }
    }

    // MARK: Copy / paste

    /// Serialize the selection as an `.excalidraw` payload for the pasteboard.
    func copyData() -> Data? {
        let elements = selectedElements
        guard !elements.isEmpty else { return nil }
        return try? ExcalidrawFile(elements: elements, files: filesFor(elements)).jsonData()
    }

    /// Paste elements from an `.excalidraw` payload, offset and re-id'd, and
    /// select them.
    func paste(_ data: Data, offset: Double = 10) {
        guard let file = try? ExcalidrawFile.decode(from: data), !file.elements.isEmpty else { return }
        var newIDs: [String] = []
        store.transaction { scene in
            for element in file.elements {
                var copy = element
                copy.base.id = nextID()
                copy.base.x += offset
                copy.base.y += offset
                scene.add(copy)
                newIDs.append(copy.id)
            }
            for (id, file) in file.files {
                scene.files[id] = file
            }
        }
        selectedIDs = Set(newIDs)
    }

    // MARK: Text & image creation

    /// Create an empty text element at `point` and select it. Returns its id so
    /// the UI can drive on-canvas editing; commit happens via `setText`.
    @discardableResult
    func createText(at point: Point, fontSize: Double = 20) -> String {
        let base = currentItem.makeBase(id: nextID(), seed: nextSeed(), x: point.x, y: point.y)
        let props = TextProperties(fontSize: fontSize, text: "", originalText: "")
        let element = ExcalidrawElement(base: base, kind: .text(props))
        store.modifyScene { $0.add(element) }
        selectedIDs = [element.id]
        return element.id
    }

    /// Set a text element's content (committing one undo step), or remove it if
    /// the text is empty.
    func setText(id: String, _ text: String) {
        guard let element = scene.element(id: id), case var .text(props) = element.kind else { return }
        if text.isEmpty {
            store.modifyScene { scene in
                scene = Scene(
                    elements: scene.elements.filter { $0.id != id },
                    appState: scene.appState, files: scene.files
                )
            }
            store.commit()
            selectedIDs.remove(id)
            return
        }
        store.transaction { scene in
            var e = element
            props.text = text
            props.originalText = text
            // Rough width/height estimate until full Core Text measurement (Phase 5).
            let lines = text.components(separatedBy: "\n")
            e.base.width = Double(lines.map(\.count).max() ?? 0) * props.fontSize * 0.6
            e.base.height = Double(lines.count) * props.fontSize * props.lineHeight
            e.kind = .text(props)
            scene.replace(e)
        }
    }

    /// Insert an image element backed by a stored file, and select it.
    @discardableResult
    func insertImage(
        dataURL: String, mimeType: String, at point: Point, width: Double, height: Double, created: Int = 0
    ) -> String {
        let fileId = nextID()
        let base = {
            var b = currentItem.makeBase(id: nextID(), seed: nextSeed(), x: point.x, y: point.y)
            b.width = width
            b.height = height
            b.backgroundColor = "transparent"
            return b
        }()
        let element = ExcalidrawElement(base: base, kind: .image(ImageProperties(fileId: fileId, status: .saved)))
        store.transaction { scene in
            scene.files[fileId] = BinaryFileData(mimeType: mimeType, id: fileId, dataURL: dataURL, created: created)
            scene.add(element)
        }
        selectedIDs = [element.id]
        return element.id
    }

    /// Stamp a library item (a group of elements) onto the canvas with its
    /// top-left at `point`, re-id'd, and select it.
    @discardableResult
    func insertLibraryItem(_ elements: [ExcalidrawElement], at point: Point) -> [String] {
        guard let bounds = ElementGeometry.commonBounds(elements.filter { !$0.base.isDeleted }) else { return [] }
        let dx = point.x - bounds.minX
        let dy = point.y - bounds.minY
        var newIDs: [String] = []
        store.transaction { scene in
            for element in elements where !element.base.isDeleted {
                var copy = element
                copy.base.id = nextID()
                copy.base.x += dx
                copy.base.y += dy
                scene.add(copy)
                newIDs.append(copy.id)
            }
        }
        selectedIDs = Set(newIDs)
        return newIDs
    }

    private func filesFor(_ elements: [ExcalidrawElement]) -> [String: BinaryFileData] {
        var result: [String: BinaryFileData] = [:]
        for element in elements {
            if case let .image(image) = element.kind, let fileId = image.fileId, let file = scene.files[fileId] {
                result[fileId] = file
            }
        }
        return result
    }
}
