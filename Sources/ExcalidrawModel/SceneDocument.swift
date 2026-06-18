import Foundation

/// Serialization between a `Scene` and `.excalidraw` document bytes. Loading
/// always passes through `Restore` so older/partial files are canonicalised.
/// This is the persistence core the document browser / autosave build on.
public enum SceneDocument {
    public static let fileExtension = "excalidraw"
    public static let utType = "com.excalidraw.scene"

    public static func encode(
        _ scene: Scene, source: String = "excalidraw-swift-web", prettyPrinted: Bool = true
    ) throws -> Data {
        try scene.toFile(source: source).jsonData(prettyPrinted: prettyPrinted)
    }

    public static func decode(_ data: Data) throws -> Scene {
        try Scene(file: Restore.restore(ExcalidrawFile.decode(from: data)))
    }
}
