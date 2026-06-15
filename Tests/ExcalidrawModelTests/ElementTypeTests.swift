import XCTest
@testable import ExcalidrawModel

final class ElementTypeTests: XCTestCase {
    func testRawValuesRoundTrip() throws {
        for type in ElementType.allCases {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ElementType.self, from: encoded)
            XCTAssertEqual(decoded, type)
        }
    }

    func testKnownRawValues() {
        XCTAssertEqual(ElementType.rectangle.rawValue, "rectangle")
        XCTAssertEqual(ElementType.freedraw.rawValue, "freedraw")
    }

    func testSchemaConstants() {
        XCTAssertEqual(ExcalidrawModel.schemaVersion, 2)
        XCTAssertEqual(ExcalidrawModel.fileType, "excalidraw")
    }
}
