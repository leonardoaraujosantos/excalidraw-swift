import XCTest
@testable import RoughKit

final class SeededRandomTests: XCTestCase {
    func testDeterministicForSameSeed() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededRandom(seed: 1)
        var b = SeededRandom(seed: 2)
        let seqA = (0..<10).map { _ in a.next() }
        let seqB = (0..<10).map { _ in b.next() }
        XCTAssertNotEqual(seqA, seqB)
    }

    func testValuesInUnitRange() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<1000 {
            let v = rng.next()
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
        }
    }

    func testZeroSeedIsNonDegenerate() {
        var rng = SeededRandom(seed: 0)
        XCTAssertNotEqual(rng.next(), rng.next())
    }
}
