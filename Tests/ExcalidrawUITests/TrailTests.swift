import CoreGraphics
import ExcalidrawMath
import ExcalidrawModel
import XCTest
@testable import ExcalidrawUI

final class TrailStoreTests: XCTestCase {
    func testTrailPrunesPointsPastFadeDuration() {
        let trail = TrailStore()
        trail.addLaser(Point(0, 0), now: 0)
        trail.addLaser(Point(10, 0), now: 0.1)
        XCTAssertEqual(trail.visibleLaser(now: 0.2).count, 2)
        // After the fade window, all points are gone.
        XCTAssertTrue(trail.visibleLaser(now: 1.0).isEmpty)
    }

    func testAddingPrunesStaleHistory() {
        let trail = TrailStore()
        trail.addLaser(Point(0, 0), now: 0)
        // A point well past the fade window prunes the old one on the next add.
        trail.addLaser(Point(1, 0), now: 5)
        XCTAssertEqual(trail.laser.count, 1)
    }

    func testLaserAndEraserTrailsAreSeparate() {
        let trail = TrailStore()
        trail.addLaser(Point(0, 0), now: 0)
        trail.addEraser(Point(5, 5), now: 0)
        XCTAssertEqual(trail.laser.count, 1)
        XCTAssertEqual(trail.eraser.count, 1)
        trail.clear()
        XCTAssertTrue(trail.laser.isEmpty)
        XCTAssertTrue(trail.eraser.isEmpty)
    }
}

@MainActor
final class LaserEraserToolTests: XCTestCase {
    func testLaserRecordsTrailAndCreatesNothing() {
        let m = EditorModel()
        m.select(tool: .laser)
        m.pointer(.down, at: CGPoint(x: 10, y: 10))
        m.pointer(.move, at: CGPoint(x: 60, y: 40))
        m.pointer(.up, at: CGPoint(x: 60, y: 40))
        XCTAssertFalse(m.trail.laser.isEmpty, "laser drag records a trail")
        XCTAssertTrue(m.controller.scene.visibleElements.isEmpty, "laser creates no element")
        XCTAssertEqual(m.activeTool, .laser, "laser stays active")
    }

    func testEraserRecordsTrailAndStillErases() {
        let m = EditorModel()
        m.setBackgroundColor("#a5d8ff") // filled, so the interior is hittable
        m.select(tool: .rectangle)
        m.pointer(.down, at: CGPoint(x: 10, y: 10))
        m.pointer(.move, at: CGPoint(x: 80, y: 60))
        m.pointer(.up, at: CGPoint(x: 80, y: 60))
        XCTAssertEqual(m.controller.scene.visibleElements.count, 1)

        m.select(tool: .eraser)
        m.pointer(.down, at: CGPoint(x: 40, y: 30))
        m.pointer(.move, at: CGPoint(x: 50, y: 40))
        m.pointer(.up, at: CGPoint(x: 50, y: 40))
        XCTAssertFalse(m.trail.eraser.isEmpty, "eraser drag records a trail")
        XCTAssertTrue(m.controller.scene.visibleElements.isEmpty, "eraser still erases")
    }
}
