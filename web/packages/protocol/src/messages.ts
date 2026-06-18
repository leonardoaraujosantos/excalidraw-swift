import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";

/**
 * Wire protocol version. Carried on `join` and echoed in `room-state` so a peer
 * can detect (and a future negotiation can handle) a mismatched relay/client.
 */
export const PROTOCOL_VERSION = 1;

/** A collaborator's stable identity, shown as a cursor + roster entry. */
export interface Peer {
  id: string;
  name: string;
  /** CSS colour for this peer's cursor/selection (e.g. "#e64980"). */
  color: string;
}

/** A live pointer position in *scene* coordinates (shared, not view pixels). */
export interface PointerPos {
  x: number;
  y: number;
}

/** A peer's broadcast presence: cursor, what they have selected, active tool. */
export interface Presence {
  pointer: PointerPos | null;
  selectedIds: string[];
  tool: string;
}

// ── Client → server ────────────────────────────────────────────────────────

/** Enter a room with an identity. First message a client sends. */
export interface JoinMessage {
  type: "join";
  protocol: number;
  room: string;
  peer: Peer;
}

/** Leave a room (also implied by socket close). */
export interface LeaveMessage {
  type: "leave";
  peerId: string;
}

// ── Server → client ────────────────────────────────────────────────────────

/** Sent to a client right after it joins: the roster + current scene snapshot. */
export interface RoomStateMessage {
  type: "room-state";
  protocol: number;
  /** The recipient's own peer id (assigned/confirmed by the relay). */
  you: string;
  peers: Peer[];
  elements: ExcalidrawElement[];
}

/** Broadcast when a peer joins the room. */
export interface PeerJoinedMessage {
  type: "peer-joined";
  peer: Peer;
}

/** Broadcast when a peer leaves (explicit `leave` or disconnect). */
export interface PeerLeftMessage {
  type: "peer-left";
  peerId: string;
}

// ── Bidirectional ───────────────────────────────────────────────────────────

/** Throttled presence update (cursor + selection + tool). */
export interface PresenceMessage {
  type: "presence";
  peerId: string;
  presence: Presence;
}

/** High-frequency, lossy cursor stream (frames may be dropped). */
export interface PointerMessage {
  type: "pointer";
  peerId: string;
  pointer: PointerPos;
}

/** Versioned element deltas — the core sync message; reconciled by version. */
export interface ElementUpdatesMessage {
  type: "element-updates";
  elements: ExcalidrawElement[];
}

/** Full-scene resync for late joiners / drift repair. */
export interface SceneSnapshotMessage {
  type: "scene-snapshot";
  elements: ExcalidrawElement[];
}

/** Liveness heartbeat; `t` is the sender's clock (ms) echoed back in `ack`. */
export interface PingMessage {
  type: "ping";
  t: number;
}

export interface AckMessage {
  type: "ack";
  t: number;
}

/** The full set of protocol messages, discriminated by `type`. */
export type Message =
  | JoinMessage
  | LeaveMessage
  | RoomStateMessage
  | PeerJoinedMessage
  | PeerLeftMessage
  | PresenceMessage
  | PointerMessage
  | ElementUpdatesMessage
  | SceneSnapshotMessage
  | PingMessage
  | AckMessage;

export type MessageType = Message["type"];

/** Narrow a `Message` by its `type` tag. */
export type MessageOf<T extends MessageType> = Extract<Message, { type: T }>;

export const MESSAGE_TYPES: readonly MessageType[] = [
  "join",
  "leave",
  "room-state",
  "peer-joined",
  "peer-left",
  "presence",
  "pointer",
  "element-updates",
  "scene-snapshot",
  "ping",
  "ack",
];
