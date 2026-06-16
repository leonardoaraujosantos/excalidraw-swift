import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class StickyNoteTests: XCTestCase {
    func testCreatesFilledContainerWithBoundText() {
        let ec = EditorController()
        let note = ec.createStickyNote(at: Point(20, 20))
        let container = ec.scene.element(id: note.container)
        let text = ec.scene.element(id: note.text)

        // Container is a solid filled rounded rectangle.
        guard case .rectangle = container?.kind else { return XCTFail("container should be a rectangle") }
        XCTAssertEqual(container?.base.fillStyle, .solid)
        XCTAssertEqual(container?.base.backgroundColor, EditorController.stickyNoteColor)
        XCTAssertNotNil(container?.base.roundness)
        XCTAssertTrue(container?.base.boundElements?.contains { $0.id == note.text } ?? false)

        // Text is bound to the container and grouped with it.
        guard case let .text(props) = text?.kind else { return XCTFail("text") }
        XCTAssertEqual(props.containerId, note.container)
        XCTAssertEqual(text?.base.groupIds, container?.base.groupIds)
        XCTAssertEqual(ec.selectedIDs, [note.container])
    }

    func testCustomColor() {
        let ec = EditorController()
        let note = ec.createStickyNote(at: Point(0, 0), color: "#a5d8ff")
        XCTAssertEqual(ec.scene.element(id: note.container)?.base.backgroundColor, "#a5d8ff")
    }

    func testBoundTextHitFindsNote() {
        let ec = EditorController()
        let note = ec.createStickyNote(at: Point(0, 0)) // 160×160 at origin
        let hit = ec.boundTextHit(at: Point(80, 80)) // centre of the note
        XCTAssertEqual(hit?.container, note.container)
        XCTAssertEqual(hit?.text, note.text)
    }

    func testEmptyContainerTextIsKept() {
        let ec = EditorController()
        let note = ec.createStickyNote(at: Point(0, 0))
        ec.setText(id: note.text, "hello")
        ec.setText(id: note.text, "") // clearing keeps the bound text element
        XCTAssertNotNil(ec.scene.element(id: note.text))
        guard case let .text(props) = ec.scene.element(id: note.text)?.kind else { return XCTFail("text") }
        XCTAssertEqual(props.text, "")
    }

    func testMovingNoteKeepsTextGrouped() {
        let ec = EditorController()
        let note = ec.createStickyNote(at: Point(0, 0))
        // Both share a group id, so a group move carries the text along.
        let group = ec.scene.element(id: note.container)?.base.groupIds.first
        XCTAssertNotNil(group)
        XCTAssertEqual(ec.scene.element(id: note.text)?.base.groupIds.first, group)
    }
}
