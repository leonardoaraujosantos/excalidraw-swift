import Foundation

/// Deterministic pseudo-random generator seeded per element.
///
/// rough.js produces its hand-drawn look by perturbing vertices with a
/// seeded RNG (`element.seed`), so the same element always renders identically.
/// Reproducing that determinism is essential for golden-image tests and for
/// matching excalidraw.com output. This mirrors rough.js's generator, which
/// advances a 31-bit linear congruential sequence and normalizes to [0, 1).
///
/// See `packages/element/src/shape.ts` (`generateRoughOptions`, `element.seed`).
public struct SeededRandom: Sendable {
    private var state: UInt32

    public init(seed: UInt32) {
        // Avoid a zero state, which would make the sequence degenerate.
        state = seed == 0 ? 1 : seed
    }

    /// Next value in [0, 1), advancing the generator. Same algorithm rough.js uses.
    public mutating func next() -> Double {
        state = (state &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
        return Double(state) / Double(0x7FFF_FFFF)
    }
}

public enum RoughKit {
    /// Default roughness (upstream `ROUGHNESS.artist`).
    public static let defaultRoughness = 1.0
}
