import type { ExcalidrawElement } from "@xs/model";
import { type Message, PROTOCOL_VERSION, type Peer, reconcileElements } from "@xs/protocol";

/** A batch of messages the transport should send to the listed connections. */
export interface Outbound {
  to: string[];
  message: Message;
}

interface Room {
  /** peerId → its peer record + owning connection. */
  peers: Map<string, { peer: Peer; connId: string }>;
  /** Reconciled scene snapshot, served to late joiners. */
  elements: Map<string, ExcalidrawElement>;
}

interface ConnState {
  room: string | null;
  peerId: string | null;
}

/**
 * The pure room/presence/scene state machine behind the WebSocket relay,
 * factored out so it can be unit-tested without sockets. Every handler takes a
 * connection id + a decoded {@link Message} and returns the {@link Outbound}
 * batches to send — no I/O of its own. The relay keeps a per-room scene snapshot
 * (reconciled with `@xs/protocol`) so a late joiner receives the current scene.
 */
export class RelayCore {
  private readonly rooms = new Map<string, Room>();
  private readonly conns = new Map<string, ConnState>();

  /** Register a fresh connection (before it has joined a room). */
  connect(connId: string): void {
    this.conns.set(connId, { room: null, peerId: null });
  }

  /** Handle a decoded message from `connId`. */
  receive(connId: string, message: Message): Outbound[] {
    switch (message.type) {
      case "join":
        return this.onJoin(connId, message);
      case "leave":
        return this.leaveRoom(connId);
      case "presence":
      case "pointer":
      case "element-updates":
      case "scene-snapshot":
        return this.onShared(connId, message);
      case "ping":
        return [{ to: [connId], message: { type: "ack", t: message.t } }];
      default:
        // Server-origin messages (room-state, peer-joined/left, ack) from a
        // client are not meaningful; ignore them.
        return [];
    }
  }

  /** Handle a dropped connection (socket close). */
  disconnect(connId: string): Outbound[] {
    const out = this.leaveRoom(connId);
    this.conns.delete(connId);
    return out;
  }

  private onJoin(connId: string, message: Extract<Message, { type: "join" }>): Outbound[] {
    const conn = this.conns.get(connId);
    if (conn === undefined) return [];
    // If this connection was already in a room, leave it first.
    const left = conn.room !== null ? this.leaveRoom(connId) : [];

    const room = this.roomFor(message.room);
    conn.room = message.room;
    conn.peerId = message.peer.id;
    room.peers.set(message.peer.id, { peer: message.peer, connId });

    const out: Outbound[] = [...left];
    out.push({
      to: [connId],
      message: {
        type: "room-state",
        protocol: PROTOCOL_VERSION,
        you: message.peer.id,
        peers: [...room.peers.values()].map((p) => p.peer),
        elements: [...room.elements.values()],
      },
    });
    const others = this.otherConns(room, connId);
    if (others.length > 0)
      out.push({ to: others, message: { type: "peer-joined", peer: message.peer } });
    return out;
  }

  private onShared(connId: string, message: Message): Outbound[] {
    const conn = this.conns.get(connId);
    if (conn?.room == null) return [];
    const room = this.rooms.get(conn.room);
    if (room === undefined) return [];

    // Keep the room snapshot current so late joiners get the latest scene.
    if (message.type === "element-updates") {
      const merged = reconcileElements([...room.elements.values()], message.elements);
      room.elements = new Map(merged.map((el) => [el.id, el]));
    } else if (message.type === "scene-snapshot") {
      room.elements = new Map(message.elements.map((el) => [el.id, el]));
    }

    const others = this.otherConns(room, connId);
    return others.length > 0 ? [{ to: others, message }] : [];
  }

  private leaveRoom(connId: string): Outbound[] {
    const conn = this.conns.get(connId);
    if (conn?.room == null || conn.peerId == null) return [];
    const roomName = conn.room;
    const peerId = conn.peerId;
    const room = this.rooms.get(roomName);
    conn.room = null;
    conn.peerId = null;
    if (room === undefined) return [];

    room.peers.delete(peerId);
    const others = this.otherConns(room, connId);
    if (room.peers.size === 0) this.rooms.delete(roomName); // drop empty rooms
    return others.length > 0 ? [{ to: others, message: { type: "peer-left", peerId } }] : [];
  }

  private roomFor(name: string): Room {
    let room = this.rooms.get(name);
    if (room === undefined) {
      room = { peers: new Map(), elements: new Map() };
      this.rooms.set(name, room);
    }
    return room;
  }

  private otherConns(room: Room, exceptConnId: string): string[] {
    const out: string[] = [];
    for (const { connId } of room.peers.values()) {
      if (connId !== exceptConnId) out.push(connId);
    }
    return out;
  }

  // ── Introspection (for tests / health checks) ──────────────────────────────

  /** Number of active rooms. */
  get roomCount(): number {
    return this.rooms.size;
  }

  /** The peers currently in `room`. */
  peersIn(room: string): Peer[] {
    const r = this.rooms.get(room);
    return r === undefined ? [] : [...r.peers.values()].map((p) => p.peer);
  }

  /** The current scene snapshot for `room`. */
  sceneOf(room: string): ExcalidrawElement[] {
    const r = this.rooms.get(room);
    return r === undefined ? [] : [...r.elements.values()];
  }
}
