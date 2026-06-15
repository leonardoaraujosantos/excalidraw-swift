import ExcalidrawRender
import SwiftUI

/// Placeholder canvas surface. The real two-layer `Canvas` (static scene +
/// interactive overlay) and the raw-`UITouch` input view arrive in Phase 2–3.
public struct CanvasPlaceholderView: View {
    @State private var viewport = Viewport()

    public init() {}

    public var body: some View {
        ZStack {
            Color(white: 0.98).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Excalidraw-Swift")
                    .font(.title2.weight(.semibold))
                Text("Canvas scaffold — Phase 0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
