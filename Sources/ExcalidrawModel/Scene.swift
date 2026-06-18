import Foundation

/// In-memory editing model: the ordered element list plus the document's app
/// state and file store. Provides id lookup and a mutation helper that maintains
/// element versioning, mirroring upstream `mutateElement`.
public struct Scene: Equatable, Sendable {
    public private(set) var elements: [ExcalidrawElement]
    public var appState: AppState
    public var files: [String: BinaryFileData]

    private var indexByID: [String: Int]

    public init(
        elements: [ExcalidrawElement] = [],
        appState: AppState = AppState(),
        files: [String: BinaryFileData] = [:]
    ) {
        self.elements = elements
        self.appState = appState
        self.files = files
        indexByID = Self.buildIndex(elements)
    }

    public init(file: ExcalidrawFile) {
        self.init(elements: file.elements, appState: file.appState, files: file.files)
    }

    public func toFile(source: String = "excalidraw-swift-web") -> ExcalidrawFile {
        ExcalidrawFile(source: source, elements: elements, appState: appState, files: files)
    }

    public func element(id: String) -> ExcalidrawElement? {
        guard let i = indexByID[id] else { return nil }
        return elements[i]
    }

    /// Non-deleted elements in document order.
    public var visibleElements: [ExcalidrawElement] {
        elements.filter { !$0.base.isDeleted }
    }

    public mutating func add(_ element: ExcalidrawElement) {
        indexByID[element.id] = elements.count
        elements.append(element)
    }

    /// Apply a change to an element and bump its version (`version`,
    /// `versionNonce`, `updated`) so it reconciles like an upstream edit.
    @discardableResult
    public mutating func mutate(
        id: String,
        timestamp: Int? = nil,
        versionNonce: Int? = nil,
        _ change: (inout ExcalidrawElement) -> Void
    ) -> Bool {
        guard let i = indexByID[id] else { return false }
        change(&elements[i])
        elements[i].base.version += 1
        if let versionNonce { elements[i].base.versionNonce = versionNonce }
        if let timestamp { elements[i].base.updated = timestamp }
        return true
    }

    /// Replace the entire ordered element list (e.g. after a z-order change),
    /// rebuilding the id index.
    public mutating func replaceAll(_ elements: [ExcalidrawElement]) {
        self.elements = elements
        indexByID = Self.buildIndex(elements)
    }

    /// Replace an element in place by id, without bumping its version. Used for
    /// live interaction updates (drag/resize); the net change is captured when
    /// the editor commits to history.
    @discardableResult
    public mutating func replace(_ element: ExcalidrawElement) -> Bool {
        guard let i = indexByID[element.id] else { return false }
        elements[i] = element
        return true
    }

    /// Soft-delete (Excalidraw keeps deleted elements for history/collab).
    @discardableResult
    public mutating func remove(id: String, timestamp: Int? = nil) -> Bool {
        mutate(id: id, timestamp: timestamp) { $0.base.isDeleted = true }
    }

    /// Apply a `SceneDelta`, preserving element order. Insertions (a change with
    /// a non-nil `after` for an unknown id) are appended; removals drop the id.
    public mutating func apply(_ delta: SceneDelta) {
        guard !delta.isEmpty else { return }
        var byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var order = elements.map(\.id)
        for (id, change) in delta.changes {
            if let after = change.after {
                if byID[id] == nil { order.append(id) }
                byID[id] = after
            } else {
                byID[id] = nil
                order.removeAll { $0 == id }
            }
        }
        elements = order.compactMap { byID[$0] }
        indexByID = Self.buildIndex(elements)
    }

    private static func buildIndex(_ elements: [ExcalidrawElement]) -> [String: Int] {
        var map: [String: Int] = [:]
        map.reserveCapacity(elements.count)
        for (i, element) in elements.enumerated() {
            map[element.id] = i
        }
        return map
    }
}
