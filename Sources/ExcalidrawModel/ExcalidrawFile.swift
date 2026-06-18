import Foundation

/// A persisted image/binary referenced by an image element (`BinaryFileData`).
public struct BinaryFileData: Codable, Equatable, Sendable {
    public var mimeType: String
    public var id: String
    public var dataURL: String
    public var created: Int
    public var lastRetrieved: Int?
    public var version: Int?

    public init(
        mimeType: String, id: String, dataURL: String, created: Int,
        lastRetrieved: Int? = nil, version: Int? = nil
    ) {
        self.mimeType = mimeType
        self.id = id
        self.dataURL = dataURL
        self.created = created
        self.lastRetrieved = lastRetrieved
        self.version = version
    }
}

/// Editor state carried in a `.excalidraw` file. Only a subset of the full
/// runtime AppState is persisted, and the subset varies by export source, so we
/// preserve the raw key/value bag verbatim (lossless round-trip) and expose
/// typed accessors for the common keys.
public struct AppState: Codable, Equatable, Sendable {
    public var raw: [String: JSONValue]

    public init(raw: [String: JSONValue] = [:]) {
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = (try? container.decode([String: JSONValue].self)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public var viewBackgroundColor: String? {
        if case let .string(value)? = raw["viewBackgroundColor"] { return value }
        return nil
    }

    public var gridModeEnabled: Bool? {
        if case let .bool(value)? = raw["gridModeEnabled"] { return value }
        return nil
    }
}

/// The top-level `.excalidraw` document envelope.
public struct ExcalidrawFile: Codable, Equatable, Sendable {
    public var type: String
    public var version: Int
    public var source: String
    public var elements: [ExcalidrawElement]
    public var appState: AppState
    public var files: [String: BinaryFileData]

    public init(
        type: String = ExcalidrawSchema.fileType,
        version: Int = ExcalidrawSchema.schemaVersion,
        source: String = "excalidraw-swift-web",
        elements: [ExcalidrawElement] = [],
        appState: AppState = AppState(),
        files: [String: BinaryFileData] = [:]
    ) {
        self.type = type
        self.version = version
        self.source = source
        self.elements = elements
        self.appState = appState
        self.files = files
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ExcalidrawSchema.fileType
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? ExcalidrawSchema.schemaVersion
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        elements = try c.decodeIfPresent([ExcalidrawElement].self, forKey: .elements) ?? []
        appState = try c.decodeIfPresent(AppState.self, forKey: .appState) ?? AppState()
        files = try c.decodeIfPresent([String: BinaryFileData].self, forKey: .files) ?? [:]
    }
}
