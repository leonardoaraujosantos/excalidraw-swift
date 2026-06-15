import CoreGraphics
import ExcalidrawMath
import XCTest
@testable import ExcalidrawRender

final class ViewportTests: XCTestCase {
    func testSceneViewRoundTrip() {
        let viewport = Viewport(scrollX: 30, scrollY: -10, zoom: 2)
        let scene = Point(12, 7)
        let view = viewport.sceneToView(scene)
        let back = viewport.viewToScene(view)
        XCTAssertEqual(back.x, scene.x, accuracy: ExcalidrawMath.precision)
        XCTAssertEqual(back.y, scene.y, accuracy: ExcalidrawMath.precision)
    }

    func testIdentityViewport() {
        let viewport = Viewport()
        XCTAssertEqual(viewport.sceneToView(Point(5, 5)), Point(5, 5))
    }

    func testZoomRange() {
        XCTAssertEqual(ExcalidrawRender.zoomRange.lowerBound, 0.1)
        XCTAssertEqual(ExcalidrawRender.zoomRange.upperBound, 30)
    }

    func testAffineTransformMatchesSceneToView() {
        let viewport = Viewport(scrollX: 30, scrollY: -10, zoom: 2)
        let scene = Point(12, 7)
        let expected = viewport.sceneToView(scene)
        let mapped = CGPoint(x: scene.x, y: scene.y).applying(viewport.affineTransform)
        XCTAssertEqual(mapped.x, expected.x, accuracy: ExcalidrawMath.precision)
        XCTAssertEqual(mapped.y, expected.y, accuracy: ExcalidrawMath.precision)
    }
}
