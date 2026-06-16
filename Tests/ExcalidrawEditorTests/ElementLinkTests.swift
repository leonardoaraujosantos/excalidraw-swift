import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class ElementLinkTests: XCTestCase {
    private func editor() -> EditorController {
        var b = BaseProperties(id: "r"); b.width = 50; b.height = 50
        let ec = EditorController(scene: Scene(elements: [ExcalidrawElement(base: b, kind: .rectangle)]))
        ec.selectAll()
        return ec
    }

    func testSetAndClearLink() {
        let ec = editor()
        ec.setLink("https://example.com")
        XCTAssertEqual(ec.scene.element(id: "r")?.base.link, "https://example.com")
        XCTAssertEqual(ec.selectionLink, "https://example.com")
        ec.setLink("   ")
        XCTAssertNil(ec.scene.element(id: "r")?.base.link)
    }

    func testLinkIsUndoable() {
        let ec = editor()
        ec.setLink("https://a.com")
        XCTAssertTrue(ec.undo())
        XCTAssertNil(ec.scene.element(id: "r")?.base.link)
    }

    func testSelectionLinkNilForMultiSelect() {
        var b2 = BaseProperties(id: "r2"); b2.x = 100; b2.width = 50; b2.height = 50
        let ec = editor()
        ec.store.modifyScene { $0.add(ExcalidrawElement(base: b2, kind: .rectangle)) }
        ec.selectAll()
        ec.setLink("https://x.com")
        XCTAssertNil(ec.selectionLink) // more than one selected
    }
}
