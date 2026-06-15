import SwiftUI
import XCTest
@testable import ExcalidrawUI

final class CanvasPlaceholderViewTests: XCTestCase {
    func testViewConstructsAndProducesBody() {
        let view = CanvasPlaceholderView()
        // Exercising `body` ensures the view graph compiles and evaluates.
        _ = view.body
    }
}
