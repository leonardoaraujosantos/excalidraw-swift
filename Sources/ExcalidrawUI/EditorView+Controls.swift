import ExcalidrawModel
import SwiftUI

/// Properties-bar controls (custom color picker, arrowhead pickers) and the
/// laser/eraser trail overlay. Split out of `EditorView` to keep it small.
extension EditorView {
    /// Native color picker for arbitrary stroke/background colors. The iOS system
    /// picker includes a screen **eyedropper**, so this also covers that gap.
    func customColorPicker(
        current: String, id: String, default fallback: String, action: @escaping (String) -> Void
    ) -> some View {
        ColorPicker("", selection: Binding(
            get: { Color(hex: current == "transparent" ? fallback : current) },
            set: { action($0.hexString) }
        ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28)
            .accessibilityIdentifier("\(id)-color-picker")
    }

    static var arrowheadOptions: [(Arrowhead?, String)] {
        [(nil, "None"), (.arrow, "Arrow"), (.triangle, "Triangle"), (.diamond, "Diamond")]
    }

    /// Start/end arrowhead pickers for the selected/active arrow.
    var arrowheadControls: some View {
        HStack(spacing: 6) {
            arrowheadMenu(icon: "arrow.left", current: model.startArrowhead, id: "start") {
                model.setStartArrowhead($0)
            }
            arrowheadMenu(icon: "arrow.right", current: model.endArrowhead, id: "end") {
                model.setEndArrowhead($0)
            }
        }
    }

    private func arrowheadMenu(
        icon: String, current: Arrowhead?, id: String, action: @escaping (Arrowhead?) -> Void
    ) -> some View {
        Menu {
            ForEach(Self.arrowheadOptions, id: \.1) { head, name in
                Button { action(head) } label: {
                    if current == head { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
                .accessibilityIdentifier("arrowhead-\(id)-\(name)")
            }
        } label: {
            Image(systemName: icon)
        }
        .accessibilityIdentifier("arrowhead-\(id)")
    }

    /// A fading trail overlay, animated while the laser or eraser tool is active.
    @ViewBuilder
    var trailOverlay: some View {
        if model.activeTool == .laser || model.activeTool == .eraser {
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    drawTrail(model.trail.visibleLaser(now: now), now: now, color: .red, width: 4, context: context)
                    drawTrail(model.trail.visibleEraser(now: now), now: now, color: .gray, width: 10, context: context)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func drawTrail(
        _ dots: [TrailStore.Dot], now: TimeInterval, color: Color, width: CGFloat, context: GraphicsContext
    ) {
        guard dots.count > 1 else { return }
        for i in 1 ..< dots.count {
            let a = model.viewport.sceneToView(dots[i - 1].position)
            let b = model.viewport.sceneToView(dots[i].position)
            let opacity = max(0, 1 - (now - dots[i].time) / TrailStore.fadeDuration)
            var path = Path()
            path.move(to: CGPoint(x: a.x, y: a.y))
            path.addLine(to: CGPoint(x: b.x, y: b.y))
            context.stroke(
                path, with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
