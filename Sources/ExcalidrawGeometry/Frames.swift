import ExcalidrawMath
import ExcalidrawModel
import Foundation

/// Frame membership helpers (`packages/element/src/frame.ts`, simplified).
/// A frame is a container; elements whose centre falls inside its bounds belong
/// to it (`frameId`).
public enum Frames {
    public static func isFrame(_ element: ExcalidrawElement) -> Bool {
        switch element.kind {
        case .frame, .magicframe: true
        default: false
        }
    }

    /// The id of the topmost frame containing `element`'s centre, or `nil`.
    /// Frames themselves are never nested here.
    public static func frame(containing element: ExcalidrawElement, in elements: [ExcalidrawElement]) -> String? {
        guard !isFrame(element) else { return nil }
        let b = ElementGeometry.bounds(element)
        let center = Point((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2)
        for frame in elements.reversed() where isFrame(frame) && !frame.base.isDeleted {
            if ElementGeometry.bounds(frame).contains(center) { return frame.id }
        }
        return nil
    }

    /// Non-deleted elements that belong to the given frame.
    public static func children(ofFrame frameID: String, in elements: [ExcalidrawElement]) -> [ExcalidrawElement] {
        elements.filter { !$0.base.isDeleted && $0.base.frameId == frameID }
    }
}
