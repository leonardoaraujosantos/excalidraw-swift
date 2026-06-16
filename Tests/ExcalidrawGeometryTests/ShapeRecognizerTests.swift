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

    /// Draw a stroke that traces a generated shape's vertices (closed).
    private func trace(_ vertices: [Point], perEdge: Int = 10, jitter: Double = 0) -> [Point] {
        stroke(vertices, closed: true, perEdge: perEdge, jitter: jitter)
    }

    private let box = BoundingBox(minX: 0, minY: 0, maxX: 200, maxY: 200)

    func testRecognizesPentagon() {
        let pts = trace(ShapeGenerator.regularPolygon(sides: 5, in: box))
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .pentagon)
    }

    func testRecognizesHexagon() {
        let pts = trace(ShapeGenerator.regularPolygon(sides: 6, in: box))
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .hexagon)
    }

    func testRecognizesStar() {
        let pts = trace(ShapeGenerator.star(points: 5, in: box))
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .star)
    }

    func testRecognizesHeart() {
        let pts = trace(ShapeGenerator.heart(in: box), perEdge: 4)
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .heart)
    }

    func testRecognizesCloud() {
        let pts = trace(ShapeGenerator.cloud(in: box), perEdge: 3)
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .cloud)
    }

    func testRecognizesSpeechBubble() {
        let pts = trace(ShapeGenerator.speechBubble(in: box), perEdge: 4)
        XCTAssertEqual(ShapeRecognizer.recognize(pts)?.shape, .speechBubble)
    }

    func testPolygonOutputIsRegenerated() {
        // The snapped pentagon uses clean generated vertices, not the rough ones.
        let result = ShapeRecognizer.recognize(trace(ShapeGenerator.regularPolygon(sides: 5, in: box)))
        XCTAssertEqual(result?.vertices.count, 5)
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
