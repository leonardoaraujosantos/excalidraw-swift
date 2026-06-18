import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import {
  type Message,
  type Peer,
  decode,
  encode,
  message,
} from "@cyberdynecorp/excalidraw-protocol";
import { describe, expect, it } from "vitest";
import { CollabSession, type CollabSocket, reconnectingSocket } from "./collab-session.js";

const me: Peer = { id: "me", name: "Me", color: "#111" };
const alice: Peer = { id: "alice", name: "Alice", color: "#e64980" };

function el(id: string, version = 1): ExcalidrawElement {
  return { ...defaultBase(id, {}), type: "rectangle", version };
}

/** A scriptable in-memory socket for driving a CollabSession in tests. */
class FakeSocket implements CollabSocket {
  sent: Message[] = [];
  private openH: () => void = () => {};
  private msgH: (d: string) => void = () => {};
  private closeH: () => void = () => {};

  send(data: string): void {
    this.sent.push(decode(data));
  }
  close(): void {
    this.closeH();
  }
  onOpen(h: () => void): void {
    this.openH = h;
  }
  onMessage(h: (d: string) => void): void {
    this.msgH = h;
  }
  onClose(h: () => void): void {
    this.closeH = h;
  }

  // test drivers
  open(): void {
    this.openH();
  }
  deliver(msg: Message): void {
    this.msgH(encode(msg));
  }
  last(): Message {
    return this.sent[this.sent.length - 1]!;
  }
}

function session(
  socket: FakeSocket,
  captured: { scene: ExcalidrawElement[]; remote: ExcalidrawElement[] },
) {
  return new CollabSession(socket, me, "room", {
    onScene: (els) => {
      captured.scene = els;
    },
    onRemoteElements: (els) => {
      captured.remote = els;
    },
  });
}

describe("CollabSession", () => {
  it("sends join on open", () => {
    const socket = new FakeSocket();
    session(socket, { scene: [], remote: [] });
    socket.open();
    expect(socket.last()).toEqual(message("join", { protocol: 1, room: "room", peer: me }));
  });

  it("applies room-state: records its id, roster (minus self), and scene", () => {
    const socket = new FakeSocket();
    const cap = { scene: [] as ExcalidrawElement[], remote: [] as ExcalidrawElement[] };
    const s = session(socket, cap);
    socket.open();
    socket.deliver(
      message("room-state", { protocol: 1, you: "me", peers: [me, alice], elements: [el("x")] }),
    );
    expect(s.you).toBe("me");
    expect([...s.peers.keys()]).toEqual(["alice"]); // self excluded
    expect(cap.scene.map((e) => e.id)).toEqual(["x"]);
  });

  it("reconciles remote element-updates via the hook", () => {
    const socket = new FakeSocket();
    const cap = { scene: [] as ExcalidrawElement[], remote: [] as ExcalidrawElement[] };
    session(socket, cap);
    socket.open();
    socket.deliver(message("element-updates", { elements: [el("y", 3)] }));
    expect(cap.remote.map((e) => [e.id, e.version])).toEqual([["y", 3]]);
  });

  it("tracks peer join/leave and live cursors", () => {
    const socket = new FakeSocket();
    const s = session(socket, { scene: [], remote: [] });
    socket.open();
    socket.deliver(message("room-state", { protocol: 1, you: "me", peers: [me], elements: [] }));

    socket.deliver(message("peer-joined", { peer: alice }));
    expect(s.peers.has("alice")).toBe(true);

    socket.deliver(message("pointer", { peerId: "alice", pointer: { x: 5, y: 6 } }));
    expect(s.cursors.get("alice")?.pointer).toEqual({ x: 5, y: 6 });

    socket.deliver(
      message("presence", {
        peerId: "alice",
        presence: { pointer: { x: 7, y: 8 }, selectedIds: ["x"], tool: "rectangle" },
      }),
    );
    expect(s.cursors.get("alice")?.selectedIds).toEqual(["x"]);
    expect(s.cursors.get("alice")?.tool).toBe("rectangle");

    socket.deliver(message("peer-left", { peerId: "alice" }));
    expect(s.peers.has("alice")).toBe(false);
    expect(s.cursors.has("alice")).toBe(false);
  });

  it("broadcasts local elements, presence, and pointer", () => {
    const socket = new FakeSocket();
    const s = session(socket, { scene: [], remote: [] });
    socket.open();
    socket.deliver(message("room-state", { protocol: 1, you: "me", peers: [me], elements: [] }));

    s.broadcastElements([el("z", 2)]);
    expect(socket.last().type).toBe("element-updates");

    s.sendPointer({ x: 1, y: 2 });
    expect(socket.last()).toEqual(message("pointer", { peerId: "me", pointer: { x: 1, y: 2 } }));

    s.sendPresence({ pointer: null, selectedIds: [], tool: "selection" });
    expect(socket.last().type).toBe("presence");

    // An empty batch is not sent.
    const count = socket.sent.length;
    s.broadcastElements([]);
    expect(socket.sent.length).toBe(count);
  });
});

describe("reconnectingSocket", () => {
  it("re-dials and re-joins after an unexpected drop", () => {
    const dialed: FakeSocket[] = [];
    const socket = reconnectingSocket(
      () => {
        const s = new FakeSocket();
        dialed.push(s);
        return s;
      },
      { schedule: (_attempt, run) => run() }, // reconnect synchronously in tests
    );
    // A CollabSession sends `join` on every (re)open.
    new CollabSession(socket, me, "room", { onScene: () => {}, onRemoteElements: () => {} });

    dialed[0]!.open();
    expect(dialed.length).toBe(1);
    expect(dialed[0]!.last().type).toBe("join");

    // The transport drops (raw socket closes) → a fresh socket is dialed and re-joins.
    dialed[0]!.close();
    expect(dialed.length).toBe(2);
    dialed[1]!.open();
    expect(dialed[1]!.last().type).toBe("join");

    // Inbound on the new socket reaches the session (broadcast works through it too).
    dialed[1]!.deliver(message("room-state", { protocol: 1, you: "me", peers: [], elements: [] }));
  });

  it("stops reconnecting after an explicit close", () => {
    const dialed: FakeSocket[] = [];
    const socket = reconnectingSocket(
      () => {
        const s = new FakeSocket();
        dialed.push(s);
        return s;
      },
      { schedule: (_attempt, run) => run() },
    );
    dialed[0]!.open();
    socket.close(); // user leaves → underlying close must NOT trigger a redial
    expect(dialed.length).toBe(1);
  });
});
