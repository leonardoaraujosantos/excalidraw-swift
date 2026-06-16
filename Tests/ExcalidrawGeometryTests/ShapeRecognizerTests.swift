import ExcalidrawMath
import Foundation
import XCTest
@testable import ExcalidrawGeometry

final class ShapeRecognizerTests: XCTestCase {
    /// Sample `count` points along the polyline through `corners` (optionally
    /// closing back to the first), with a little jitter to mimic a hand stroke.
    private func stroke(_ corners: [Point], closed: Bool, perEdge: Int = 12, jitter: Double = 0) -> [Point] {
        var path = corners
        if closed { path.append(corners[0]) }
        var points: [Point] = []
        for i in 0 ..< (path.count - 1) {
            let a = path[i], b = path[i + 1]
            for s in 0 ..< perEdge {
                let t = Double(s) / Double(perEdge)
                let wob = jitter * sin(t * .pi)
                points.append(Point(a.x + (b.x - a.x) * t + wob, a.y + (b.y - a.y) * t + wob))
            }
        }
        points.append(path.last!)
        return points
    }

    func testRecognizesSquare() {
        let pts = stroke([Point(0, 0), Point(100, 0), Point(100, 100), Point(0, 100)], closed: true)
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .rectangle)
    }

    func testRecognizesTriangle() {
        let pts = stroke([Point(50, 0), Point(100, 100), Point(0, 100)], closed: true)
        let result = ShapeRecognizer.recognize(pts)
        XCTAssertEqual(result?.shape, .triangle)
        XCTAssertEqual(result?.vertices.count, 3)
    }

    func testRecognizesCircleAsEllipse() {
        var pts: [Point] = []
        for i in 0 ... 60 {
            let a = Double(i) / 60 * 2 * .pi
            pts.append(Point(50 + 50 * cos(a), 50 + 50 * sin(a)))
        }
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .ellipse)
    }

    func testRecognizesDiamond() {
        let pts = stroke([Point(50, 0), Point(100, 50), Point(50, 100), Point(0, 50)], closed: true)
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .diamond)
    }

    func testRecognizesLine() {
        let pts = (0 ... 20).map { Point(Double($0) * 5, 0) }
        let result = ShapeRecognizer.recognize(pts)
        XCTAssertEqual(result?.shape, .line)
        XCTAssertEqual(result?.vertices.count, 2)
    }

    func testToleratesJitterySquare() {
        let pts = stroke(
            [Point(0, 0), Point(120, 0), Point(120, 120), Point(0, 120)],
            closed: true, perEdge: 20, jitter: 3
        )
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .rectangle)
    }

    func testRejectsTinyStroke() {
        XCTAssertNil(ShapeRecognizer.recognize([Point(0, 0), Point(0.2, 0.1)]))
    }
}
