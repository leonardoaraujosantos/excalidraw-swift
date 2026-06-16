import ExcalidrawModel
import Foundation

/// The active editing tool.
public enum Tool: String, Sendable, CaseIterable {
    case selection
    case rectangle
    case diamond
    case ellipse
    case line
    case arrow
    case freedraw
    case text
    case frame
    case eraser
    case hand

    /// The element kind a shape tool creates, or `nil` for non-creating tools.
    var elementKind: ElementKind? {
        switch self {
        case .rectangle: .rectangle
        case .diamond: .diamond
        case .ellipse: .ellipse
        case .line: .line(LinearProperties())
        case .arrow: .arrow(ArrowProperties())
        case .freedraw: .freedraw(FreedrawProperties())
        case .frame: .frame(name: nil)
        case .selection, .eraser, .hand, .text: nil
        }
    }

    var isShape: Bool {
        elementKind != nil
    }
}
