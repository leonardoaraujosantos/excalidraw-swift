import ExcalidrawUI
import SwiftUI

@main
struct ExcalidrawApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        CanvasPlaceholderView()
    }
}
