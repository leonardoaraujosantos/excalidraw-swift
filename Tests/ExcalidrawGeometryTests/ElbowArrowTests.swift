import ExcalidrawMath
import XCTest
@testable import ExcalidrawGeometry

final class ElbowArrowTests: XCTestCase {
    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> BoundingBox {
        BoundingBox(minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    /// Every consecutive pair of points must form an axis-aligned segment.
    private func assertOrthogonal(_ points: [Point], file: StaticString = #filePath, line: UInt = #line) {
        for i in 0 ..< (points.count - 1) {
            let a = points[i], b = points[i + 1]
            let axisAligned = abs(a.x - b.x) < 1e-6 || abs(a.y - b.y) < 1e-6
            XCTAssertTrue(axisAligned, "segment \(i) (\(a)→\(b)) is not axis-aligned", file: file, line: line)
        }
    }

    func testFreeEndpointsProduceOrthogonalRoute() {
        let route = ElbowArrow.route(
            start: Point(0, 0), startBox: nil,
            end: Point(100, 60), endBox: nil
        )
        XCTAssertGreaterThanOrEqual(route.count, 2)
        XCTAssertEqual(route.first, Point(0, 0))
        XCTAssertEqual(route.last, Point(100, 60))
        assertOrthogonal(route)
    }

    func testColinearHorizontalEndpointsRouteStraight() {
        // Same y, free endpoints → a straight horizontal segment (no bends).
        let route = ElbowArrow.route(
            start: Point(0, 50), startBox: nil,
            end: Point(200, 50), endBox: nil
        )
        XCTAssertEqual(route.first, Point(0, 50))
        XCTAssertEqual(route.last, Point(200, 50))
        assertOrthogonal(route)
        for p in route {
            XCTAssertEqual(p.y, 50, accuracy: 1e-6)
        }
    }

    func testBoundBoxesRouteBetweenShapes() {
        // Two boxes separated horizontally; arrow leaves the right of A and
        // enters the left of B.
        let a = box(0, 0, 100, 100)
        let b = box(300, 0, 100, 100)
        let route = ElbowArrow.route(
            start: Point(100, 50), startBox: a,
            end: Point(300, 50), endBox: b
        )
        XCTAssertEqual(route.first, Point(100, 50))
        XCTAssertEqual(route.last, Point(300, 50))
        assertOrthogonal(route)
    }

    func testVerticallyStackedBoxesRoute() {
        let a = box(0, 0, 100, 100)
        let b = box(0, 300, 100, 100)
        let route = ElbowArrow.route(
            start: Point(50, 100), startBox: a,
            end: Point(50, 300), endBox: b
        )
        XCTAssertEqual(route.first, Point(50, 100))
        XCTAssertEqual(route.last, Point(50, 300))
        assertOrthogonal(route)
    }

    func testFixableSegmentsExcludeEndpoints() {
        // 4 points → 3 segments; only the middle (index 2) is fixable.
        let points = [Point(0, 0), Point(50, 0), Point(50, 100), Point(150, 100)]
        let segments = ElbowArrow.fixableSegments(points)
        XCTAssertEqual(segments.map(\.index), [2])
        XCTAssertFalse(segments[0].isHorizontal) // vertical segment (50,0)→(50,100)
        XCTAssertEqual(segments[0].midpoint, Point(50, 50))
    }

    func testNoFixableSegmentsForShortPaths() {
        XCTAssertTrue(ElbowArrow.fixableSegments([Point(0, 0), Point(100, 0)]).isEmpty)
        XCTAssertTrue(ElbowArrow.fixableSegments([Point(0, 0), Point(50, 0), Point(50, 50)]).isEmpty)
    }

    func testMoveVerticalSegmentShiftsItHorizontally() {
        let points = [Point(0, 0), Point(50, 0), Point(50, 100), Point(150, 100)]
        // Drag the middle vertical segment to x = 90.
        let moved = ElbowArrow.moveSegment(points, index: 2, to: Point(90, 50))
        XCTAssertEqual(moved.index, 2) // interior: shifts in place
        XCTAssertEqual(moved.points[1], Point(90, 0)) // shared with first segment
        XCTAssertEqual(moved.points[2], Point(90, 100)) // shared with last segment
        XCTAssertEqual(moved.points[0], Point(0, 0)) // endpoints unchanged
        XCTAssertEqual(moved.points[3], Point(150, 100))
        assertOrthogonal(moved.points)
    }

    func testMoveHorizontalSegmentShiftsItVertically() {
        let points = [Point(0, 0), Point(0, 50), Point(100, 50), Point(100, 150)]
        let moved = ElbowArrow.moveSegment(points, index: 2, to: Point(50, 80))
        XCTAssertEqual(moved.points[1], Point(0, 80))
        XCTAssertEqual(moved.points[2], Point(100, 80))
        assertOrthogonal(moved.points)
    }

    func testDraggingFirstSegmentInsertsBend() {
        // Single-bend arrow (3 points); the first segment is horizontal.
        let points = [Point(0, 0), Point(100, 0), Point(100, 80)]
        let moved = ElbowArrow.moveSegment(points, index: 1, to: Point(50, 30))
        XCTAssertEqual(moved.points.count, 4) // a bend was inserted
        XCTAssertEqual(moved.index, 2) // moved segment is now interior
        XCTAssertEqual(moved.points.first, Point(0, 0)) // start stays put
        XCTAssertEqual(moved.points.last, Point(100, 80)) // end stays put
        assertOrthogonal(moved.points)
    }

    func testDraggingLastSegmentInsertsBend() {
        let points = [Point(0, 0), Point(0, 80), Point(120, 80)]
        let moved = ElbowArrow.moveSegment(points, index: 2, to: Point(60, 50))
        XCTAssertEqual(moved.points.count, 4)
        XCTAssertEqual(moved.points.first, Point(0, 0))
        XCTAssertEqual(moved.points.last, Point(120, 80))
        assertOrthogonal(moved.points)
    }

    func testFollowEndpointsPreservesInteriorSegments() {
        let points = [Point(0, 0), Point(50, 0), Point(50, 100), Point(150, 100)]
        let moved = ElbowArrow.followEndpoints(points, newStart: Point(-20, 10), newEnd: Point(180, 130))
        XCTAssertEqual(moved.first, Point(-20, 10))
        XCTAssertEqual(moved.last, Point(180, 130))
        // The pinned middle segment keeps its x = 50.
        XCTAssertEqual(moved[1].x, 50)
        XCTAssertEqual(moved[2].x, 50)
        assertOrthogonal(moved)
    }

    func testDiagonalBoxesProduceBend() {
        // Offset boxes force at least one corner.
        let a = box(0, 0, 80, 80)
        let b = box(260, 200, 80, 80)
        let route = ElbowArrow.route(
            start: Point(80, 40), startBox: a,
            end: Point(260, 240), endBox: b
        )
        assertOrthogonal(route)
        XCTAssertGreaterThanOrEqual(route.count, 3) // has at least one bend
    }
}
