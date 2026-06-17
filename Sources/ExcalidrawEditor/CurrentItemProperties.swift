import ExcalidrawModel
import Foundation

/// Style properties applied to newly created elements, mirroring the
/// `currentItem*` fields of upstream AppState.
public struct CurrentItemProperties: Sendable {
    public var strokeColor: String = "#1e1e1e"
    public var backgroundColor: String = "transparent"
    public var fillStyle: FillStyle = .hachure
    public var strokeWidth: Double = 2
    public var strokeStyle: StrokeStyle = .solid
    public var roughness: Double = 1
    public var opacity: Double = 100
    public var fontFamily: Int = FontFamily.default
    public var fontSize: Double = 20
    /// Create arrows as orthogonal "elbow" arrows.
    public var elbowed: Bool = false
    /// Give new elements rounded edges/corners (splined lines, rounded rects).
    public var roundEdges: Bool = true
    /// Default arrowheads for new arrows (start is usually none, end an arrow).
    public var startArrowhead: Arrowhead?
    public var endArrowhead: Arrowhead? = .arrow

    public init() {}

    /// Build the base properties for a new element at `(x, y)` with the given id
    /// and seed, carrying these current styles.
    func makeBase(id: String, seed: Int, x: Double, y: Double) -> BaseProperties {
        BaseProperties(
            id: id, x: x, y: y, width: 0, height: 0, angle: 0,
            strokeColor: strokeColor, backgroundColor: backgroundColor,
            fillStyle: fillStyle, strokeWidth: strokeWidth, strokeStyle: strokeStyle,
            roundness: nil, roughness: roughness, opacity: opacity, seed: seed
        )
    }
}
