import CoreGraphics
import ExcalidrawModel
import XCTest
@testable import ExcalidrawUI

@MainActor
final class ArrowheadTests: XCTestCase {
    private func draw(_ m: EditorModel, from: CGPoint, to: CGPoint) {
        m.pointer(.down, at: from)
        m.pointer(.move, at: to)
        m.pointer(.up, at: to)
    }

    private func arrowProps(_ m: EditorModel) -> ArrowProperties? {
        for element in m.controller.scene.visibleElements {
            if case let .arrow(props) = element.kind { return props }
        }
        return nil
    }

    func testNewArrowUsesCurrentArrowheadDefaults() {
        let m = EditorModel()
        m.setStartArrowhead(.triangle)
        m.setEndArrowhead(.diamond)
        m.select(tool: .arrow)
        draw(m, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 60))
        let props = arrowProps(m)
        XCTAssertEqual(props?.startArrowhead, .triangle)
        XCTAssertEqual(props?.endArrowhead, .diamond)
    }

    func testSettingArrowheadAppliesToSelectedArrow() {
        let m = EditorModel()
        m.select(tool: .arrow)
        draw(m, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 60))
        // Arrow stays selected after creation; change its heads.
        m.setEndArrowhead(nil)
        m.setStartArrowhead(.arrow)
        let props = arrowProps(m)
        XCTAssertNil(props?.endArrowhead)
        XCTAssertEqual(props?.startArrowhead, .arrow)
    }

    func testDefaultEndArrowheadIsArrow() {
        let m = EditorModel()
        XCTAssertEqual(m.endArrowhead, .arrow)
        XCTAssertNil(m.startArrowhead)
    }
}
