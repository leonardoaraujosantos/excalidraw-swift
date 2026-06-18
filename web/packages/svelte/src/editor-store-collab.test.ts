import { Point } from "@cyberdynecorp/excalidraw-math";
import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { type Message, decode, encode, message } from "@cyberdynecorp/excalidraw-protocol";
import { describe, expect, it } from "vitest";
import type { CollabSocket } from "./collab-session.js";
import { EditorStore } from "./editor-store.js";

class FakeSocket implements CollabSocket {
  sent: Message[] = [];
  private msgH: (d: string) => void = () => {};
  private openH: () => void = () => {};
  send(data: string): void {
    this.sent.push(decode(data));
  }
  close(): void {}
  onOpen(h: () => void): void {
    this.openH = h;
  }
  onMessage(h: (d: string) => void): void {
    this.msgH = h;
  }
  onClose(): void {}
  open(): void {
    this.openH();
  }
  deliver(msg: Message): void {
    this.msgH(encode(msg));
  }
  updates(): Extract<Message, { type: "element-updates" }>[] {
    return this.sent.filter(
      (m): m is Extract<Message, { type: "element-updates" }> => m.type === "element-updates",
    );
  }
}

function connectedStore(): { store: EditorStore; socket: FakeSocket } {
  const store = new EditorStore();
  const socket = new FakeSocket();
  store.startCollab(socket, { id: "me", name: "Me", color: "#111" }, "room");
  socket.open();
  socket.deliver(message("room-state", { protocol: 1, you: "me", peers: [], elements: [] }));
  return { store, socket };
}

describe("EditorStore collaboration", () => {
  it("broadcasts a locally drawn element", () => {
    const { store, socket } = connectedStore();
    store.selectTool("rectangle");
    store.pointer("down", new Point(10, 10));
    store.pointer("move", new Point(60, 40));
    store.pointer("up", new Point(60, 40));

    const drawn = store.scene.visibleElements.find((e) => e.type === "rectangle")!;
    const broadcast = socket.updates().flatMap((m) => m.elements);
    expect(broadcast.some((e) => e.id === drawn.id)).toBe(true);
  });

  it("applies a remote element without an undo step and without echoing it back", () => {
    const { store, socket } = connectedStore();
    const remote: ExcalidrawElement = {
      ...defaultBase("remote", { width: 20, height: 20 }),
      type: "rectangle",
      version: 1,
    };
    socket.deliver(message("element-updates", { elements: [remote] }));

    expect(store.scene.element("remote")).toBeDefined();
    expect(store.canUndo).toBe(false); // remote edits aren't on the local undo stack
    // The applied remote element is not re-broadcast (no echo loop).
    expect(
      socket
        .updates()
        .flatMap((m) => m.elements)
        .some((e) => e.id === "remote"),
    ).toBe(false);
  });

  it("a remote element that wins reconciliation replaces the local copy", () => {
    const { store, socket } = connectedStore();
    // Seed a v1 via remote, then a v2 for the same id wins.
    socket.deliver(
      message("element-updates", {
        elements: [
          { ...defaultBase("x", { width: 10, height: 10 }), type: "rectangle", version: 1 },
        ],
      }),
    );
    socket.deliver(
      message("element-updates", {
        elements: [
          { ...defaultBase("x", { width: 99, height: 99 }), type: "rectangle", version: 2 },
        ],
      }),
    );
    expect(store.scene.element("x")?.width).toBe(99);
  });

  it("namespaces generated ids per peer to avoid collisions (regression)", () => {
    const make = (peerId: string): EditorStore => {
      const store = new EditorStore();
      const socket = new FakeSocket();
      store.startCollab(socket, { id: peerId, name: peerId, color: "#000" }, "room");
      socket.open();
      socket.deliver(message("room-state", { protocol: 1, you: peerId, peers: [], elements: [] }));
      return store;
    };
    const draw = (store: EditorStore): string => {
      store.selectTool("rectangle");
      store.pointer("down", new Point(10, 10));
      store.pointer("move", new Point(50, 50));
      store.pointer("up", new Point(50, 50));
      return store.scene.visibleElements.find((e) => e.type === "rectangle")!.id;
    };

    const aliceId = draw(make("alice"));
    const bobId = draw(make("bob"));
    expect(aliceId).not.toBe(bobId); // would collide without per-peer prefixes
    expect(aliceId.startsWith("alice-")).toBe(true);
    expect(bobId.startsWith("bob-")).toBe(true);
  });

  it("merges a reconnect snapshot: local edits survive and are re-broadcast (regression)", () => {
    const { store, socket } = connectedStore();
    // Draw locally while connected.
    store.selectTool("rectangle");
    store.pointer("down", new Point(10, 10));
    store.pointer("move", new Point(60, 40));
    store.pointer("up", new Point(60, 40));
    const localId = store.scene.visibleElements.find((e) => e.type === "rectangle")!.id;

    const before = socket.sent.length;
    // Reconnect: the relay re-sends room-state with a *different* peer's element
    // (and not ours). The merge must keep our element and re-publish it.
    const remote: ExcalidrawElement = {
      ...defaultBase("peer-x", { width: 10, height: 10 }),
      type: "ellipse",
      version: 1,
    };
    socket.deliver(
      message("room-state", { protocol: 1, you: "me", peers: [], elements: [remote] }),
    );

    expect(store.scene.element(localId)).toBeDefined(); // survived the snapshot
    expect(store.scene.element("peer-x")).toBeDefined(); // room element merged in
    const reBroadcast = socket.sent
      .slice(before)
      .filter((m) => m.type === "element-updates")
      .flatMap((m) => (m.type === "element-updates" ? m.elements : []));
    expect(reBroadcast.some((e) => e.id === localId)).toBe(true); // re-published to the room
  });

  it("loads a room snapshot on join", () => {
    const store = new EditorStore();
    const socket = new FakeSocket();
    store.startCollab(socket, { id: "me", name: "Me", color: "#111" }, "room");
    socket.open();
    socket.deliver(
      message("room-state", {
        protocol: 1,
        you: "me",
        peers: [],
        elements: [
          { ...defaultBase("seed", { width: 5, height: 5 }), type: "rectangle", version: 1 },
        ],
      }),
    );
    expect(store.scene.element("seed")).toBeDefined();
  });
});
