import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class FlowchartTests: XCTestCase {
    private func nodeEditor() -> EditorController {
        var b = BaseProperties(id: "n"); b.x = 0; b.y = 0; b.width = 100; b.height = 60
        b.backgroundColor = "#a5d8ff"
        return EditorController(scene: Scene(elements: [ExcalidrawElement(base: b, kind: .rectangle)]))
    }

    func testAddsNodeAndArrowToTheRight() throws {
        let ec = nodeEditor()
        let result = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: .right))
        let node = try XCTUnwrap(ec.scene.element(id: result.node))
        // Same shape and size, offset right by width + gap (100 + 100).
        XCTAssertEqual(node.base.x, 200, accuracy: 1e-9)
        XCTAssertEqual(node.base.y, 0, accuracy: 1e-9)
        XCTAssertEqual(node.base.width, 100)
        if case .rectangle = node.kind {} else { XCTFail("new node should be a rectangle") }
        XCTAssertEqual(ec.selectedIDs, [result.node]) // new node selected
    }

    func testArrowIsElbowAndBoundBothEnds() throws {
        let ec = nodeEditor()
        let result = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: .down))
        guard case let .arrow(props) = ec.scene.element(id: result.arrow)?.kind else { return XCTFail("arrow") }
        XCTAssertTrue(props.elbowed)
        XCTAssertEqual(props.startBinding?.elementId, "n")
        XCTAssertEqual(props.endBinding?.elementId, result.node)
    }

    func testBoundElementsRegisteredOnBothNodes() throws {
        let ec = nodeEditor()
        let result = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: .up))
        let source = try XCTUnwrap(ec.scene.element(id: "n"))
        let target = try XCTUnwrap(ec.scene.element(id: result.node))
        XCTAssertTrue(source.base.boundElements?.contains { $0.id == result.arrow } ?? false)
        XCTAssertTrue(target.base.boundElements?.contains { $0.id == result.arrow } ?? false)
    }

    func testDirectionsOffsetCorrectly() throws {
        for (direction, expected) in [
            (FlowchartDirection.left, Point(-200, 0)),
            (FlowchartDirection.up, Point(0, -160))
        ] {
            let ec = nodeEditor()
            let result = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: direction))
            let node = try XCTUnwrap(ec.scene.element(id: result.node))
            XCTAssertEqual(node.base.x, expected.x, accuracy: 1e-9, "\(direction)")
            XCTAssertEqual(node.base.y, expected.y, accuracy: 1e-9, "\(direction)")
        }
    }

    func testRejectsNonBindableSource() {
        let props = ArrowProperties(points: [Point(0, 0), Point(50, 0)])
        let ec = EditorController(scene: Scene(elements: [
            ExcalidrawElement(base: BaseProperties(id: "a"), kind: .arrow(props))
        ]))
        XCTAssertNil(ec.addFlowchartNode(from: "a", direction: .right))
    }

    func testSecondNodeSameDirectionStaggers() throws {
        let ec = nodeEditor()
        let first = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: .down))
        let second = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: .down))
        let a = try XCTUnwrap(ec.scene.element(id: first.node))
        let b = try XCTUnwrap(ec.scene.element(id: second.node))
        // The second node is offset horizontally so it doesn't overlap the first.
        XCTAssertNotEqual(a.base.x, b.base.x)
    }

    func testAddNodeIsUndoable() throws {
        let ec = nodeEditor()
        _ = try XCTUnwrap(ec.addFlowchartNode(from: "n", direction: .right))
        XCTAssertEqual(ec.scene.visibleElements.count, 3) // source + node + arrow
        XCTAssertTrue(ec.undo())
        XCTAssertEqual(ec.scene.visibleElements.count, 1)
    }
}
