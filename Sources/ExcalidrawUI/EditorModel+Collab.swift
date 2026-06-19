import ExcalidrawCollab
import ExcalidrawEditor
import ExcalidrawModel
import Foundation

/// Collaboration wiring for the SwiftUI app — the parity of the TypeScript
/// `EditorStore` collab methods. Local edits broadcast as `element-updates`;
/// remote edits are reconciled into the scene by `version`/`versionNonce`
/// (without polluting local undo); peer presence/cursors are republished for the
/// UI. The underlying `CollabClient` auto-reconnects and re-joins.
@MainActor
public extension EditorModel {
    /// Auto-join a room from launch arguments / `UserDefaults` of the form
    /// `-collabRelay ws://… -collabRoom <id> -collabName <name>` — used by the
    /// live iOS↔web collaboration UI test (and any deep-link launch).
    func joinCollabFromLaunchArguments(_ defaults: UserDefaults = .standard) {
        guard collab == nil,
              let relay = defaults.string(forKey: "collabRelay"), !relay.isEmpty,
              let room = defaults.string(forKey: "collabRoom"), !room.isEmpty,
              let url = URL(string: relay)
        else { return }
        let name = defaults.string(forKey: "collabName") ?? "iPad"
        let palette = ["#e64980", "#4263eb", "#0ca678", "#f08c00", "#ae3ec9"]
        let peer = Peer(
            id: "\(name.lowercased())-\(Int.random(in: 1000 ... 9999))",
            name: name,
            color: palette.randomElement() ?? "#e64980"
        )
        startCollab(url: url, peer: peer, room: room)
    }

    /// Join a collaboration room. Local edits sync to peers; remote edits apply
    /// reconciled. Element ids are namespaced by the peer id so two clients never
    /// collide.
    func startCollab(url: URL, peer: Peer, room: String) {
        let handlers = CollabClient.Handlers(
            onScene: { [weak self] elements in
                Task { @MainActor in self?.applyRemoteScene(elements) }
            },
            onRemoteElements: { [weak self] elements in
                Task { @MainActor in self?.applyRemoteElements(elements) }
            },
            onPeersChanged: { [weak self] peers in
                Task { @MainActor in self?.remotePeers = peers }
            },
            onCursor: { [weak self] peerId, pointer in
                Task { @MainActor in self?.remoteCursors[peerId] = pointer }
            }
        )
        let client = CollabClient(url: url, peer: peer, room: room, handlers: handlers)
        collab = client
        attachCollabSink(idPrefix: "\(peer.id)-") { [weak client] elements in
            client?.broadcastElements(elements)
        }
        client.connect()
    }

    /// Leave the room and stop collaborating.
    func stopCollab() {
        collab?.disconnect()
        collab = nil
        collabSend = nil
        collabPointerSink = nil
        collabPresenceSink = nil
        remotePeers = []
        remoteCursors = [:]
    }

    /// Surface remote presence from an embedder's own collaboration transport
    /// (the Swift parity of the web `externalCursors` bridge). Adopters wiring a
    /// custom relay instead of the built-in `startCollab` call these so the
    /// remote-cursor overlay renders. Drive `setRemotePeers` from the roster and
    /// `setRemoteCursor` from each presence/pointer update.
    func setRemotePeers(_ peers: [Peer]) {
        remotePeers = peers
    }

    func setRemoteCursor(peerId: String, pointer: PointerPos?) {
        if let pointer {
            remoteCursors[peerId] = pointer
        } else {
            remoteCursors.removeValue(forKey: peerId)
        }
    }

    /// Wire the outbound sinks + id namespace (shared by `startCollab` and tests).
    /// `sendPointer`/`sendPresence` let an embedder with a custom transport
    /// publish the local cursor to peers (the built-in `collab` client handles
    /// this itself, so it omits them).
    func attachCollabSink(
        idPrefix: String,
        send: @escaping ([ExcalidrawElement]) -> Void,
        sendPointer: ((PointerPos) -> Void)? = nil,
        sendPresence: ((Presence) -> Void)? = nil
    ) {
        controller.idPrefix = idPrefix
        collabSend = send
        collabPointerSink = sendPointer
        collabPresenceSink = sendPresence
        syncBroadcastBaseline()
    }

    /// Apply a room snapshot (join / reconnect): merge with the local scene by
    /// reconciliation so edits made while briefly offline survive, then
    /// re-broadcast anything the room does not yet have.
    func applyRemoteScene(_ elements: [ExcalidrawElement]) {
        let merged = Reconcile.reconcileElements(local: controller.scene.elements, remote: elements)
        controller.applyElements(merged)
        lastBroadcast.removeAll()
        for element in elements {
            lastBroadcast[element.id] = element.base.version
        }
        revision += 1 // didSet → broadcastLocalChanges → publishes local-only/newer
    }

    /// Merge a versioned remote batch into the scene (reconciled, no undo step,
    /// no echo).
    func applyRemoteElements(_ elements: [ExcalidrawElement]) {
        let merged = Reconcile.reconcileElements(local: controller.scene.elements, remote: elements)
        controller.applyElements(merged)
        syncBroadcastBaseline()
        revision += 1 // didSet → broadcastLocalChanges → diff empty → no echo
    }

    /// Mark every current element as already broadcast (after applying remote).
    func syncBroadcastBaseline() {
        lastBroadcast.removeAll()
        for element in controller.scene.elements {
            lastBroadcast[element.id] = element.base.version
        }
    }

    /// Send elements whose version changed since the last broadcast.
    func broadcastLocalChanges() {
        guard let collabSend else { return }
        var changed: [ExcalidrawElement] = []
        for element in controller.scene.elements where lastBroadcast[element.id] != element.base.version {
            changed.append(element)
            lastBroadcast[element.id] = element.base.version
        }
        if !changed.isEmpty { collabSend(changed) }
    }
}
