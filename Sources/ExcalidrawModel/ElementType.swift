import Foundation

/// The element/tool types supported by Excalidraw.
///
/// Source of truth: `packages/element/src/types.ts` and the tool list in
/// `packages/common/src/constants.ts`. `selection` is ephemeral and never
/// persisted. The concrete element model (associated values per case) lands
/// in Phase 1.
public enum ElementType: String, Codable, CaseIterable, Sendable {
    case selection
    case rectangle
    case diamond
    case ellipse
    case arrow
    case line
    case freedraw
    case text
    case image
    case frame
    case magicframe
    case embeddable
    case iframe
}

public enum ExcalidrawModel {
    /// `.excalidraw` JSON schema version we read/write (upstream `VERSIONS.excalidraw`).
    public static let schemaVersion = 2

    /// File `type` discriminator in the `.excalidraw` envelope.
    public static let fileType = "excalidraw"
}
