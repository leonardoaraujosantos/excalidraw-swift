import XCTest
@testable import FreehandKit

final class FreehandKitTests: XCTestCase {
    func testSizeMultiplier() {
        XCTAssertEqual(FreehandKit.sizeMultiplier, 4.25, accuracy: 1e-9)
    }
}
