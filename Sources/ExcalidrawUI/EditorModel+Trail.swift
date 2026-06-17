import CoreGraphics
import ExcalidrawEditor
import ExcalidrawMath
import Foundation

/// Tap-to-create tools (text / post-it / table) and the ephemeral laser pointer,
/// plus eraser-trail recording. Extracted from `pointer(...)` to keep it small.
extension EditorModel {
    /// Handle the pointer for tap/ephemeral tools. Returns `true` when the event
    /// was fully handled (the caller should not forward it to the controller).
    func handlePointerTool(phase: PointerPhase, viewPoint: CGPoint, scenePoint: Point) -> Bool {
        switch activeTool {
        case .text:
            if phase == .down { beginTextEditing(at: viewPoint, scenePoint: scenePoint) }
            return true
        case .postit:
            if phase == .down { beginStickyNote(at: viewPoint, scenePoint: scenePoint) }
            return true
        case .table:
            if phase == .down {
                controller.createTable(at: scenePoint)
                revertToSelection()
                revision += 1
            }
            return true
        case .laser:
            // Ephemeral pointer: record a fading trail, create nothing.
            if phase != .up { trail.addLaser(scenePoint, now: Self.now) }
            revision += 1
            return true
        case .eraser:
            // Record the eraser trail, then let the controller do the erasing.
            if phase != .up { trail.addEraser(scenePoint, now: Self.now) }
            return false
        default:
            return false
        }
    }

    static var now: TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }
}
