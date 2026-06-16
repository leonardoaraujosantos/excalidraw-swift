import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawEditor

final class ElbowArrowEditorTests: XCTestCase {
    private func assertOrthogonal(_ points: [Point]) {
        for i in 0 ..< (points.count - 1) {
            let a = points[i], b = points[i + 1]
            XCTAssertTrue(abs(a.x - b.x) < 1e-6 || abs(a.y - b.y) < 1e-6, "segment \(i) not axis-aligned")
        }
    }

    func testCreatingElbowArrowProducesOrthogonalPoints() {
        let ec = EditorController()
        ec.currentItem.elbowed = true
        ec.setTool(.arrow)
        ec.pointerDown(PointerEvent(scenePoint: Point(0, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(120, 80), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(120, 80), phase: .up))

        guard case let .arrow(props) = ec.scene.visibleElements.first?.kind else { return XCTFail("arrow") }
        XCTAssertTrue(props.elbowed)
        XCTAssertGreaterThanOrEqual(props.points.count, 2)
        assertOrthogonal(props.points)
    }

    func testNonElbowArrowStaysTwoPoints() {
        let ec = EditorController()
        ec.setTool(.arrow)
        ec.pointerDown(PointerEvent(scenePoint: Point(0, 0), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(120, 80), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(120, 80), phase: .up))
        guard case let .arrow(props) = ec.scene.visibleElements.first?.kind else { return XCTFail("arrow") }
        XCTAssertFalse(props.elbowed)
        XCTAssertEqual(props.points.count, 2)
    }

    private func fourPointElbow() -> EditorController {
        let props = ArrowProperties(
            points: [Point(0, 0), Point(50, 0), Point(50, 100), Point(150, 100)],
            endArrowhead: .arrow, elbowed: true
        )
        var base = BaseProperties(id: "arrow"); base.width = 150; base.height = 100
        return EditorController(scene: Scene(elements: [ExcalidrawElement(base: base, kind: .arrow(props))]))
    }

    func testMoveElbowSegmentPinsFixedSegment() throws {
        let ec = fourPointElbow()
        ec.moveElbowSegment(id: "arrow", index: 2, to: Point(90, 50))
        guard case let .arrow(props) = ec.scene.element(id: "arrow")?.kind else { return XCTFail("arrow") }
        XCTAssertEqual(props.fixedSegments?.count, 1)
        XCTAssertEqual(props.fixedSegments?.first?.index, 2)
        let base = try XCTUnwrap(ec.scene.element(id: "arrow")?.base)
        let global = props.points.map { Point(base.x + $0.x, base.y + $0.y) }
        XCTAssertEqual(global[1].x, 90, accuracy: 1e-9)
        XCTAssertEqual(global[2].x, 90, accuracy: 1e-9)
    }

    func testSegmentHandlesViaLinearEditDrag() throws {
        let ec = fourPointElbow()
        XCTAssertTrue(ec.beginLinearEdit(at: Point(50, 50)))
        ec.pointerDown(PointerEvent(scenePoint: Point(50, 50), phase: .down))
        ec.pointerMove(PointerEvent(scenePoint: Point(85, 50), phase: .move))
        ec.pointerUp(PointerEvent(scenePoint: Point(85, 50), phase: .up))
        guard case let .arrow(props) = ec.scene.element(id: "arrow")?.kind else { return XCTFail("arrow") }
        XCTAssertEqual(props.fixedSegments?.first?.index, 2)
        let base = try XCTUnwrap(ec.scene.element(id: "arrow")?.base)
        XCTAssertEqual(base.x + props.points[1].x, 85, accuracy: 1e-9)
    }

    func testPinnedSegmentSurvivesEndpointReroute() throws {
        let ec = fourPointElbow()
        ec.moveElbowSegment(id: "arrow", index: 2, to: Point(90, 50))
        ec.store.modifyScene { scene in
            guard var arrow = scene.element(id: "arrow"), case var .arrow(props) = arrow.kind,
                  let last = props.points.last else { return }
            props.points[props.points.count - 1] = Point(last.x + 40, last.y + 30)
            arrow.kind = .arrow(props)
            scene.replace(arrow)
        }
        ec.routeElbowArrow("arrow")
        guard case let .arrow(props) = ec.scene.element(id: "arrow")?.kind else { return XCTFail("arrow") }
        let base = try XCTUnwrap(ec.scene.element(id: "arrow")?.base)
        let global = props.points.map { Point(base.x + $0.x, base.y + $0.y) }
        XCTAssertEqual(global[1].x, 90, accuracy: 1e-6)
        XCTAssertEqual(global[2].x, 90, accuracy: 1e-6)
        assertOrthogonal(global)
    }

    func testBoundElbowArrowReroutesOnTargetMove() throws {
        var a = BaseProperties(id: "a"); a.x = 0; a.y = 0; a.width = 100; a.height = 100; a.backgroundColor = "#f00"
        var b = BaseProperties(id: "b"); b.x = 300; b.y = 0; b.width = 100; b.height = 100; b.backgroundColor = "#f00"
        let arrowProps = ArrowProperties(
            points: [Point(0, 0), Point(200, 50)],
            startBinding: FixedPointBinding(elementId: "a", fixedPoint: Point(1, 0.5), mode: .orbit),
            endBinding: FixedPointBinding(elementId: "b", fixedPoint: Point(0, 0.5), mode: .orbit),
            endArrowhead: .arrow, elbowed: true
        )
        var arrowBase = BaseProperties(id: "arrow"); arrowBase.x = 100; arrowBase.y = 50
        let scene = Scene(elements: [
            ExcalidrawElement(base: a, kind: .rectangle),
            ExcalidrawElement(base: b, kind: .rectangle),
            ExcalidrawElement(base: arrowBase, kind: .arrow(arrowProps))
        ])
        let ec = EditorController(scene: scene)
        ec.routeElbowArrow("arrow")

        guard case let .arrow(routed) = ec.scene.element(id: "arrow")?.kind else { return XCTFail("arrow") }
        XCTAssertGreaterThanOrEqual(routed.points.count, 2)
        let base = try XCTUnwrap(ec.scene.element(id: "arrow")?.base)
        let global = routed.points.map { Point(base.x + $0.x, base.y + $0.y) }
        assertOrthogonal(global)
    }
}
