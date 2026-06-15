import Foundation

/// Pressure-aware freehand stroke outlines (port of `perfect-freehand`).
///
/// Generates the filled outline polygon for a freedraw element from its input
/// points and per-point pressures. The full algorithm lands in Phase 4; this
/// placeholder exists to wire the package graph and tests.
public enum FreehandKit {
    /// Stroke size multiplier applied to `strokeWidth`, matching upstream
    /// freedraw tuning in `packages/element/src/shape.ts`.
    public static let sizeMultiplier = 4.25
}
