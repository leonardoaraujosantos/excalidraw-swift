#if canImport(UIKit)
    import ExcalidrawEditor
    import SwiftUI
    import UIKit

    /// Captures raw `UITouch` input (pressure, pencil vs finger, palm rejection,
    /// two-finger pan/zoom) and forwards it to the `EditorModel`. SwiftUI gestures
    /// don't expose `force`/coalesced touches, so this drops to UIKit.
    struct PointerInputView: UIViewRepresentable {
        let model: EditorModel

        func makeUIView(context _: Context) -> TouchCaptureView {
            let view = TouchCaptureView()
            view.model = model
            return view
        }

        func updateUIView(_ view: TouchCaptureView, context _: Context) {
            view.model = model
        }
    }

    final class TouchCaptureView: UIView {
        var model: EditorModel?

        private var pencilActive = false
        private var gesturing = false
        private var lastCentroid: CGPoint = .zero
        private var lastDistance: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("not used")
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let all = event?.allTouches ?? touches
            if all.count >= 2 { beginGesture(all); return }
            guard let touch = touches.first else { return }
            if touch.type == .pencil { pencilActive = true }
            guard accept(touch) else { return }
            // Double-tap enters line/arrow point-editing or image crop mode.
            if touch.tapCount == 2 {
                model?.beginEditMode(at: touch.location(in: self))
                return
            }
            forward(.down, touch)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            let all = event?.allTouches ?? touches
            if gesturing || all.count >= 2 { updateGesture(all); return }
            guard let touch = touches.first, accept(touch) else { return }
            forward(.move, touch)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            endTouches(touches, event: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            endTouches(touches, event: event)
        }

        private func endTouches(_ touches: Set<UITouch>, event: UIEvent?) {
            if gesturing {
                let remaining = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
                if remaining.count < 2 { gesturing = false }
            } else if let touch = touches.first, accept(touch) {
                forward(.up, touch)
            }
            let pencilStillDown = (event?.allTouches ?? []).contains {
                $0.type == .pencil && $0.phase != .ended && $0.phase != .cancelled
            }
            if !pencilStillDown { pencilActive = false }
        }

        /// Palm rejection: once a pencil is active, ignore finger touches.
        private func accept(_ touch: UITouch) -> Bool {
            !(pencilActive && touch.type != .pencil)
        }

        private func forward(_ phase: PointerPhase, _ touch: UITouch) {
            let type: PointerType = touch.type == .pencil ? .pen : .touch
            let pressure = touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 0.5
            model?.pointer(phase, at: touch.location(in: self), type: type, pressure: pressure)
        }

        // MARK: Two-finger pan / pinch

        private func beginGesture(_ touches: Set<UITouch>) {
            gesturing = true
            let pts = touches.map { $0.location(in: self) }
            lastCentroid = centroid(pts)
            lastDistance = spread(pts, around: lastCentroid)
        }

        private func updateGesture(_ touches: Set<UITouch>) {
            let pts = touches.map { $0.location(in: self) }
            guard pts.count >= 2 else { return }
            let centroidNow = centroid(pts)
            let distanceNow = spread(pts, around: centroidNow)
            let translation = CGSize(width: centroidNow.x - lastCentroid.x, height: centroidNow.y - lastCentroid.y)
            let scale = lastDistance > 0 ? Double(distanceNow / lastDistance) : 1
            model?.panZoom(translation: translation, scale: scale)
            lastCentroid = centroidNow
            lastDistance = distanceNow
        }

        private func centroid(_ pts: [CGPoint]) -> CGPoint {
            guard !pts.isEmpty else { return .zero }
            let sum = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(pts.count), y: sum.y / CGFloat(pts.count))
        }

        private func spread(_ pts: [CGPoint], around center: CGPoint) -> CGFloat {
            pts.reduce(0) { $0 + hypot($1.x - center.x, $1.y - center.y) } / CGFloat(max(pts.count, 1))
        }
    }
#endif
