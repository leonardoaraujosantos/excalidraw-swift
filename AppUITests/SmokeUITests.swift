import XCTest

/// Phase 0 smoke test: the app launches on the target simulator. Real
/// end-to-end drawing flows (draw → move → resize → undo → export) arrive in
/// Phase 3 once the interaction loop exists.
final class SmokeUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Excalidraw-Swift"].waitForExistence(timeout: 10))
    }
}
