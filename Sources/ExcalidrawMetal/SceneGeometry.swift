import CoreGraphics
import ExcalidrawGeometry
import ExcalidrawMath
import ExcalidrawModel
import ExcalidrawRender
import Foundation
import FreehandKit
import RoughKit

/// Turns a `Scene` into GPU-ready colored triangles, in scene coordinates.
///
/// Tessellated here: the hand-drawn rough shapes (rectangle, diamond, ellipse,
/// line, arrow) and freedraw strokes (from their perfect-freehand outline) —
/// that is where the GPU pays off (many fill/stroke triangles). Text, images,
/// frames, embeddables and any frame-clipped child stay with the Core Graphics
/// overlay pass, which already handles their typography, decoding and clipping
/// correctly. `handledIDs` is exactly the set the overlay must skip so nothing
/// is drawn twice.
public struct SceneGeometry {
    /// Interleaved vertex data: `[x, y, packedRGBA]` per vertex (3 floats),
    /// three vertices per triangle, in scene coordinates. The color is an RGBA8
    /// value bit-cast into a float; the shader unpacks it. The shader projects
    /// position to clip space.
    public private(set) var vertices: [Float] = []
    /// Element IDs the GPU drew; the CG overlay pass skips these.
    public private(set) var handledIDs: Set<String> = []

    /// Floats per vertex: x, y, packed color.
    static let floatsPerVertex = 3

    public var triangleCount: Int {
        vertices.count / (Self.floatsPerVertex * 3)
    }

    public var isEmpty: Bool {
        vertices.isEmpty
    }

    private let theme: Theme
    /// Extra scene-unit margin so wide strokes near the viewport edge aren't
    /// culled (matches `SceneRenderer.cullingMargin`).
    private static let cullingMargin = 100.0

    public init(
        scene: Scene, theme: Theme, skipping: Set<String> = [], visibleRegion: BoundingBox? = nil,
        shapeCache: ShapeCache = ShapeCache(), geometryCache: GeometryCache? = nil
    ) {
        self.theme = theme
        build(
            scene: scene, skipping: skipping, visibleRegion: visibleRegion,
            shapeCache: shapeCache, geometryCache: geometryCache
        )
    }

    private mutating func build(
        scene: Scene, skipping: Set<String>, visibleRegion: BoundingBox?,
        shapeCache: ShapeCache, geometryCache: GeometryCache?
    ) {
        // Cull off-screen elements (parity with SceneRenderer) so a big scene
        // only tessellates/draws what's visible. Culling selects elements; each
        // element's cached vertices stay valid, so it composes with the cache.
        let candidates = visibleRegion.map {
            Culling.visible(scene.visibleElements, in: $0, margin: Self.cullingMargin)
        } ?? scene.visibleElements

        for element in candidates
            where !skipping.contains(element.id) && isTessellatable(element) {
            // Rough shapes need a drawable; freedraw is tessellated from its
            // perfect-freehand outline and has none.
            let drawable = Self.isFreedraw(element) ? nil : shapeCache.drawable(for: element)
            if !Self.isFreedraw(element), drawable == nil { continue }
            let verts = geometryCache?.vertices(for: element, theme: theme) {
                Self.elementVertices(element: element, drawable: drawable, theme: theme)
            } ?? Self.elementVertices(element: element, drawable: drawable, theme: theme)
            vertices.append(contentsOf: verts)
            handledIDs.insert(element.id)
        }
    }

    /// GPU-eligible elements: rough shapes and freedraw with a solid stroke and
    /// no frame clipping. Everything else (text/image/frame/embeddable, dashed
    /// or dotted strokes, framed children) falls through to Core Graphics.
    private func isTessellatable(_ element: ExcalidrawElement) -> Bool {
        guard element.base.frameId == nil, element.base.strokeStyle == .solid else { return false }
        switch element.kind {
        case .rectangle, .diamond, .ellipse, .line, .arrow, .freedraw: return true
        default: return false
        }
    }

    private static func isFreedraw(_ element: ExcalidrawElement) -> Bool {
        if case .freedraw = element.kind { return true }
        return false
    }

    /// Tessellate a single element into interleaved packed-color vertex floats
    /// in scene coordinates. Static and self-contained so a `GeometryCache` can
    /// memoize the result per element. `drawable` is nil for freedraw.
    static func elementVertices(element: ExcalidrawElement, drawable: Drawable?, theme: Theme) -> [Float] {
        let base = element.base
        let opacity = Float(base.opacity / 100)
        let transform = elementTransform(base)
        let strokeRGBA = rgba(base.strokeColor, opacity: opacity, theme: theme)

        if case let .freedraw(props) = element.kind {
            return freedrawVertices(props, base: base, color: strokeRGBA, transform: transform)
        }
        guard let drawable else { return [] }
        let fillRGBA = drawable.options.fill.flatMap { rgba($0, opacity: opacity, theme: theme) }

        var out: [Float] = []
        for set in drawable.sets {
            let subpaths = Tessellator.flatten(set.ops)
            switch set.type {
            case .fillPath:
                guard let fillRGBA else { continue }
                for sub in subpaths {
                    emit(Tessellator.fillTriangles(sub), color: fillRGBA, transform: transform, into: &out)
                }
            case .fillSketch:
                guard let fillRGBA else { continue }
                let weight = drawable.options.fillWeight > 0 ? drawable.options.fillWeight : base.strokeWidth / 2
                for sub in subpaths {
                    emit(
                        Tessellator.strokeTriangles(sub, halfWidth: weight / 2),
                        color: fillRGBA,
                        transform: transform,
                        into: &out
                    )
                }
            case .path:
                guard let strokeRGBA else { continue }
                for sub in subpaths {
                    emit(
                        Tessellator.strokeTriangles(sub, halfWidth: base.strokeWidth / 2),
                        color: strokeRGBA,
                        transform: transform,
                        into: &out
                    )
                }
            }
        }

        if case let .arrow(props) = element.kind, let strokeRGBA {
            appendArrowheads(props, base: base, color: strokeRGBA, transform: transform, into: &out)
        }
        return out
    }

    // MARK: - Freedraw (mirrors SceneRenderer.drawFreedraw)

    /// Tessellate a freedraw stroke: build the perfect-freehand outline (a
    /// closed filled polygon) and triangulate it, filled with the stroke color.
    private static func freedrawVertices(
        _ props: FreedrawProperties, base: BaseProperties, color: SIMDColor?, transform: (Point) -> Point
    ) -> [Float] {
        guard let color, !props.points.isEmpty else { return [] }
        let inputs = props.points.enumerated().map { index, p in
            FreehandPoint(x: p.x, y: p.y, pressure: index < props.pressures.count ? props.pressures[index] : 0.5)
        }
        let options = FreehandOptions(strokeWidth: base.strokeWidth, simulatePressure: props.simulatePressure)
        let outline = FreehandKit.strokeOutline(inputs, options: options)
        guard outline.count > 2 else { return [] }
        var out: [Float] = []
        emit(Tessellator.fillTriangles(outline), color: color, transform: transform, into: &out)
        return out
    }

    // MARK: - Arrowheads (mirrors SceneRenderer.drawArrowhead)

    private static func appendArrowheads(
        _ props: ArrowProperties, base: BaseProperties, color: SIMDColor,
        transform: (Point) -> Point, into out: inout [Float]
    ) {
        let pts = props.points
        guard pts.count >= 2 else { return }
        if let head = props.endArrowhead {
            appendArrowhead(
                at: pts[pts.count - 1],
                from: pts[pts.count - 2],
                head: head,
                base: base,
                color: color,
                transform: transform,
                into: &out
            )
        }
        if let head = props.startArrowhead {
            appendArrowhead(
                at: pts[0],
                from: pts[1],
                head: head,
                base: base,
                color: color,
                transform: transform,
                into: &out
            )
        }
    }

    private static func appendArrowhead(
        at tip: Point, from prev: Point, head: Arrowhead, base: BaseProperties,
        color: SIMDColor, transform: (Point) -> Point, into out: inout [Float]
    ) {
        let dir = Vector(from: tip, origin: prev).normalized()
        guard dir.magnitude > 0 else { return }
        let segLength = tip.distance(to: prev)
        let size = Swift.min(20, segLength * 0.5) + base.strokeWidth
        let angle = 25.0 * .pi / 180
        let back = Vector(-dir.u, -dir.v)
        func rotated(_ v: Vector, by a: Double) -> Vector {
            Vector(v.u * cos(a) - v.v * sin(a), v.u * sin(a) + v.v * cos(a))
        }
        let b1 = rotated(back, by: angle).scaled(by: size)
        let b2 = rotated(back, by: -angle).scaled(by: size)
        let p1 = Point(tip.x + b1.u, tip.y + b1.v)
        let p2 = Point(tip.x + b2.u, tip.y + b2.v)

        if head == .triangle || head == .diamond {
            emit([p1, tip, p2], color: color, transform: transform, into: &out)
        } else {
            emit(
                Tessellator.strokeTriangles([p1, tip, p2], halfWidth: base.strokeWidth / 2),
                color: color,
                transform: transform,
                into: &out
            )
        }
    }

    // MARK: - Emit / transform / color

    private static func emit(
        _ triangles: [Point], color: SIMDColor, transform: (Point) -> Point, into out: inout [Float]
    ) {
        // Do NOT call reserveCapacity per emit: a tight per-call reservation
        // defeats Array's geometric growth and turns the many appends across a
        // scene into O(n²) reallocation. Plain append keeps amortized O(1).
        // Color is packed RGBA8 bit-cast into one float (the shader unpacks it).
        let packed = Float(bitPattern: color.packed)
        for p in triangles {
            let t = transform(p)
            out.append(Float(t.x))
            out.append(Float(t.y))
            out.append(packed)
        }
    }

    /// Element-local → scene transform: rotate about the element centre, then
    /// translate to the element origin (matches `SceneRenderer.drawElement`).
    static func elementTransform(_ base: BaseProperties) -> (Point) -> Point {
        let cx = base.width / 2, cy = base.height / 2
        let angle = base.angle
        let cosA = cos(angle), sinA = sin(angle)
        return { p in
            var x = p.x, y = p.y
            if angle != 0 {
                let dx = x - cx, dy = y - cy
                x = cx + dx * cosA - dy * sinA
                y = cy + dx * sinA + dy * cosA
            }
            return Point(x + base.x, y + base.y)
        }
    }

    struct SIMDColor {
        var r, g, b, a: Float

        /// RGBA8 in byte order r,g,b,a — matches Metal's
        /// `unpack_unorm4x8_to_float` (x=byte0 … w=byte3).
        var packed: UInt32 {
            func byte(_ v: Float) -> UInt32 {
                UInt32((max(0, min(1, v)) * 255).rounded())
            }
            return byte(r) | (byte(g) << 8) | (byte(b) << 16) | (byte(a) << 24)
        }
    }

    private static func rgba(_ string: String, opacity: Float, theme: Theme) -> SIMDColor? {
        guard !ColorParser.isTransparent(string), let base = ColorParser.cgColor(string) else { return nil }
        let themed = ThemeFilter.apply(base, theme: theme)
        guard let c = themed.components, c.count >= 3 else { return nil }
        let alpha = Float(c.count >= 4 ? c[3] : 1) * opacity
        return SIMDColor(r: Float(c[0]), g: Float(c[1]), b: Float(c[2]), a: alpha)
    }
}
