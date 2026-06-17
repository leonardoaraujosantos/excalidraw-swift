import XCTest

/// End-to-end editor flows on device/simulator. Pencil/pressure and the exact
/// rendering math are covered by unit tests; these drive the real UI to make
/// sure the tools, generators, and the layered/gesture rendering paths work
/// (and don't crash or garble) on real hardware.
final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var canvas: XCUIElement!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.wait(for: .runningForeground, timeout: 10), true)
        canvas = app.otherElements["excalidraw-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    }

    private func drag(_ from: CGVector, _ to: CGVector, duration: TimeInterval = 0.1) {
        canvas.coordinate(withNormalizedOffset: from)
            .press(forDuration: duration, thenDragTo: canvas.coordinate(withNormalizedOffset: to))
    }

    private func tap(_ tool: String) {
        let button = app.buttons[tool]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing \(tool)")
        button.tap()
    }

    func testDrawTextAndExportFlow() {
        tap("tool-rectangle")
        drag(CGVector(dx: 0.3, dy: 0.3), CGVector(dx: 0.6, dy: 0.55))

        tap("tool-freedraw")
        drag(CGVector(dx: 0.2, dy: 0.7), CGVector(dx: 0.5, dy: 0.8))

        tap("tool-text")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.42)).tap()
        let textField = app.textFields["text-editor"]
        if textField.waitForExistence(timeout: 5) {
            textField.tap(); textField.typeText("Hi")
            app.buttons["text-done"].tap()
        }

        app.buttons["export"].tap()
        XCTAssertTrue(app.staticTexts["exported-confirmation"].waitForExistence(timeout: 5))
    }

    func testStickyNoteTableAndChart() {
        // Sticky note: drop and label it.
        tap("tool-postit")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
        let noteText = app.textFields["text-editor"]
        if noteText.waitForExistence(timeout: 5) {
            noteText.tap(); noteText.typeText("Todo")
            app.buttons["text-done"].tap()
        }

        // Table: drop a grid.
        tap("tool-table")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.3)).tap()

        // Chart: open the sheet, enter values, insert.
        tap("chart")
        let values = app.textFields["chart-values"]
        if values.waitForExistence(timeout: 5) {
            values.tap(); values.typeText("4, 8, 15, 16, 23")
            app.buttons["chart-insert"].tap()
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testStrokeWidthAndColors() {
        // Draw a rectangle (it stays selected), then restyle it: stroke colour,
        // fill colour, and stroke width.
        tap("tool-rectangle")
        drag(CGVector(dx: 0.3, dy: 0.3), CGVector(dx: 0.6, dy: 0.55))

        tap("stroke-#e03131") // red stroke
        tap("bg-#a5d8ff") // blue fill

        // Bump the stroke width via the stepper's increment.
        let stepper = app.steppers["stroke-width"]
        if stepper.waitForExistence(timeout: 5) {
            let increment = stepper.buttons["Increment"]
            if increment.exists { increment.tap(); increment.tap() } else { stepper.tap() }
        }

        app.buttons["export"].tap()
        XCTAssertTrue(app.staticTexts["exported-confirmation"].waitForExistence(timeout: 5))
    }

    func testMovePanAndZoom() {
        // Draw a rectangle, then move it with the selection tool (exercises the
        // static/dynamic layered render path).
        tap("tool-rectangle")
        drag(CGVector(dx: 0.3, dy: 0.3), CGVector(dx: 0.55, dy: 0.5))
        tap("tool-selection")
        drag(CGVector(dx: 0.3, dy: 0.4), CGVector(dx: 0.5, dy: 0.6)) // grab the left edge and move

        // Pan/zoom the board (exercises the gesture-snapshot path).
        canvas.pinch(withScale: 1.8, velocity: 1.2) // zoom in
        canvas.pinch(withScale: 0.6, velocity: -1.2) // zoom out

        // Footer zoom controls.
        if app.buttons["zoom-in"].waitForExistence(timeout: 5) {
            app.buttons["zoom-in"].tap()
            app.buttons["zoom-out"].tap()
            app.buttons["zoom-fit"].tap()
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(canvas.exists)
    }

    func testAddPointsToLine() {
        // Draw a line, enter point-edit (double-tap), then drag near its
        // midpoint to insert/move a point.
        tap("tool-line")
        drag(CGVector(dx: 0.25, dy: 0.4), CGVector(dx: 0.7, dy: 0.4))
        tap("tool-selection")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.475, dy: 0.4)).doubleTap()
        drag(CGVector(dx: 0.475, dy: 0.4), CGVector(dx: 0.475, dy: 0.6)) // pull the midpoint down
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(canvas.exists)
    }

    func testLaserAndArrowheadAndColorPicker() {
        // Arrowhead picker appears with the arrow tool; pick a triangle end.
        tap("tool-arrow")
        drag(CGVector(dx: 0.25, dy: 0.3), CGVector(dx: 0.6, dy: 0.4))
        if app.buttons["arrowhead-end"].waitForExistence(timeout: 3) {
            app.buttons["arrowhead-end"].tap()
            app.buttons["arrowhead-end-Triangle"].tap()
        }
        // Custom color picker exists in the properties bar.
        XCTAssertTrue(app.buttons["stroke-color-picker"].exists)

        // Laser pointer: select it and sweep — leaves a fading trail, no element.
        tap("tool-laser")
        drag(CGVector(dx: 0.3, dy: 0.5), CGVector(dx: 0.7, dy: 0.6), duration: 0.4)
        let laser = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        laser.name = "laser-trail"; laser.lifetime = .keepAlways; add(laser)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testMetalRendererDrawMoveAndZoom() throws {
        let toggle = app.buttons["renderer-toggle"]
        guard toggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Metal renderer unavailable on this device")
        }

        // Draw shapes (rect/ellipse/arrow) + a text label in the default Core
        // Graphics renderer first, and capture what's on screen.
        tap("tool-rectangle")
        drag(CGVector(dx: 0.25, dy: 0.25), CGVector(dx: 0.5, dy: 0.45))
        tap("tool-ellipse")
        drag(CGVector(dx: 0.55, dy: 0.25), CGVector(dx: 0.75, dy: 0.45))
        tap("tool-arrow")
        drag(CGVector(dx: 0.3, dy: 0.62), CGVector(dx: 0.7, dy: 0.62))
        tap("tool-text")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)).tap()
        let textField = app.textFields["text-editor"]
        if textField.waitForExistence(timeout: 5) {
            textField.tap(); textField.typeText("Metal")
            app.buttons["text-done"].tap()
        }
        tap("tool-selection")
        snapshot("editor-coregraphics")

        // Switch to the Metal hybrid (GPU shapes + CG text overlay) — the same
        // scene must still be visible — and capture it.
        toggle.tap()
        sleep(1)
        snapshot("editor-metal-hybrid")

        // Move a shape and zoom under the GPU backend; capture the zoomed view.
        drag(CGVector(dx: 0.3, dy: 0.35), CGVector(dx: 0.45, dy: 0.5))
        canvas.pinch(withScale: 2.2, velocity: 1.4)
        sleep(1)
        snapshot("editor-metal-zoomed")
        canvas.pinch(withScale: 0.5, velocity: -1.4)

        // Export still works with the GPU backend active.
        app.buttons["export"].tap()
        XCTAssertTrue(app.staticTexts["exported-confirmation"].waitForExistence(timeout: 5))

        // Switch back to Core Graphics and confirm the app is still alive.
        toggle.tap()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(canvas.exists)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRendererBenchmarkScreenShowsResults() {
        // Open the on-screen renderer benchmark. It defaults to Live mode, which
        // renders the moving stress scene on screen with a live FPS readout.
        app.buttons["benchmark"].tap()
        XCTAssertTrue(app.staticTexts["FPS"].waitForExistence(timeout: 5), "live readout missing")
        // Let a few animated frames render, then capture what's on screen.
        sleep(2)
        let live = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        live.name = "renderer-benchmark-live"
        live.lifetime = .keepAlways
        add(live)

        // Switch to the direct-to-drawable backend (when Metal is available) and
        // confirm it keeps rendering on screen.
        let direct = app.buttons["live-backend-Direct"]
        if direct.waitForExistence(timeout: 3) {
            direct.tap()
            sleep(2)
            XCTAssertTrue(app.staticTexts["FPS"].exists)
            let directShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            directShot.name = "renderer-benchmark-direct"
            directShot.lifetime = .keepAlways
            add(directShot)
        }

        // Switch to the Table mode and run the headless comparison.
        app.segmentedControls["benchmark-mode"].buttons["Table"].tap()
        let run = app.buttons["benchmark-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        let firstRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'benchmark-row-'")
        ).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30), "benchmark produced no result rows")
        let table = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        table.name = "renderer-benchmark-table"
        table.lifetime = .keepAlways
        add(table)

        app.buttons["benchmark-done"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    }
}
