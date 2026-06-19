import CoreGraphics
import ExcalidrawCollab
import ExcalidrawEditor
import ExcalidrawModel
import XCTest
@testable import ExcalidrawUI

/// The Swift parity of `editor-store-collab.test.ts`: the SwiftUI app's
/// `EditorModel` collaboration wiring, exercised with a captured broadcast sink
/// (no real socket).
@MainActor
final class CollabModelTests: XCTestCase {
    private func draw(_ model: EditorModel, _ tool: Tool, from: CGPoint, to: CGPoint) {
        model.select(tool: tool)
        model.pointer(.down, at: from)
        model.pointer(.move, at: to)
        model.pointer(.up, at: to)
    }

    private func element(_ id: String, version: Int, width: Double = 20) -> ExcalidrawElement {
        var base = BaseProperties(id: id)
        base.version = version
        base.width = width
        base.height = 20
        return ExcalidrawElement(base: base, kind: .rectangle)
    }

    func testBroadcastsALocalDraw() {
        let model = EditorModel()
        var sent: [ExcalidrawElement] = []
        model.attachCollabSink(idPrefix: "alice-") { sent.append(contentsOf: $0) }
        draw(model, .rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
        XCTAssertTrue(sent.contains { $0.type == "rectangle" })
    }

    func testAppliesRemoteWithoutUndoOrEcho() {
        let model = EditorModel()
        var sent: [ExcalidrawElement] = []
        model.attachCollabSink(idPrefix: "me-") { sent.append(contentsOf: $0) }
        model.applyRemoteElements([element("remote", version: 1)])
        XCTAssertNotNil(model.controller.scene.element(id: "remote"))
        XCTAssertFalse(model.controller.canUndo) // remote edits aren't on the local undo stack
        XCTAssertFalse(sent.contains { $0.id == "remote" }) // no echo
    }

    func testRemoteWinnerReplacesLocal() {
        let model = EditorModel()
        model.attachCollabSink(idPrefix: "me-") { _ in }
        model.applyRemoteElements([element("x", version: 1, width: 10)])
        model.applyRemoteElements([element("x", version: 2, width: 99)])
        XCTAssertEqual(model.controller.scene.element(id: "x")?.base.width, 99)
    }

    func testReconnectMergeSurvivesLocalEdits() throws {
        let model = EditorModel()
        var sent: [ExcalidrawElement] = []
        model.attachCollabSink(idPrefix: "me-") { sent.append(contentsOf: $0) }
        draw(model, .rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
        let localID = try XCTUnwrap(model.controller.scene.visibleElements.first { $0.type == "rectangle" }?.id)

        sent.removeAll()
        // Reconnect: the room snapshot has a different peer's element, not ours.
        model.applyRemoteScene([element("peer-x", version: 1)])

        XCTAssertNotNil(model.controller.scene.element(id: localID)) // survived the merge
        XCTAssertNotNil(model.controller.scene.element(id: "peer-x")) // merged in
        XCTAssertTrue(sent.contains { $0.id == localID }) // re-broadcast to the room
    }

    func testBroadcastsLocalPointerAndPresenceThroughSinks() {
        // Regression: an embedder with a custom transport (no built-in `collab`
        // client) must still publish its local cursor, or peers can't see where
        // it is working. The pointer sink fires on every move; presence on .up.
        let model = EditorModel()
        var pointers: [PointerPos] = []
        var presences: [Presence] = []
        model.attachCollabSink(
            idPrefix: "me-",
            send: { _ in },
            sendPointer: { pointers.append($0) },
            sendPresence: { presences.append($0) }
        )
        model.select(tool: .rectangle)
        model.pointer(.down, at: CGPoint(x: 10, y: 10))
        model.pointer(.move, at: CGPoint(x: 40, y: 30))
        model.pointer(.up, at: CGPoint(x: 60, y: 40))

        XCTAssertEqual(pointers.count, 3) // down + move + up
        XCTAssertEqual(pointers.last?.x, 60)
        XCTAssertEqual(presences.count, 1) // presence published once, on pointer up
    }

    func testIdPrefixNamespacesIds() throws {
        let alice = EditorModel()
        alice.attachCollabSink(idPrefix: "alice-") { _ in }
        let bob = EditorModel()
        bob.attachCollabSink(idPrefix: "bob-") { _ in }

        draw(alice, .rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        draw(bob, .rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))

        let aliceID = try XCTUnwrap(alice.controller.scene.visibleElements.first { $0.type == "rectangle" }?.id)
        let bobID = try XCTUnwrap(bob.controller.scene.visibleElements.first { $0.type == "rectangle" }?.id)
        XCTAssertNotEqual(aliceID, bobID) // would collide without per-peer prefixes
        XCTAssertTrue(aliceID.hasPrefix("alice-"))
        XCTAssertTrue(bobID.hasPrefix("bob-"))
    }
}
