import CoreGraphics
import Foundation

/// Caches the rasterized "static" layer of the canvas — every element except
/// the one(s) currently being drawn or moved — so that during an interaction
/// each frame is a cheap blit of the cached image plus a redraw of only the
/// in-flight elements, instead of repainting the whole scene (Phase 7.5 Stage B).
///
/// The cache is keyed on an opaque `token`: the caller holds it fixed for the
/// duration of an interaction (the static content doesn't change while you drag
/// one element) and changes/invalidates it when the committed scene, viewport,
/// size, or theme changes.
public final class StaticLayerCache {
    private var image: CGImage?
    private var token: Int?

    public init() {}

    /// Return the cached image for `token`, building (and caching) it via
    /// `build` on a miss. Returns `nil` only if `build` returns `nil`.
    public func image(token: Int, build: () -> CGImage?) -> CGImage? {
        if self.token != token || image == nil {
            image = build()
            self.token = token
        }
        return image
    }

    /// Drop the cached image (e.g. when an interaction ends or the scene commits).
    public func invalidate() {
        image = nil
        token = nil
    }

    /// Whether a usable image is cached for `token`.
    public func isValid(for token: Int) -> Bool {
        image != nil && self.token == token
    }
}
