import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { type Message, type Peer, message } from "@cyberdynecorp/excalidraw-protocol";
import { describe, expect, it } from "vitest";
import { type Outbound, RelayCore } from "./relay-core.js";

const peerA: Peer = { id: "A", name: "Alice", color: "#e64980" };
const peerB: Peer = { id: "B", name: "Bob", color: "#4263eb" };

function el(id: string, version: number): ExcalidrawElement {
  return { ...defaultBase(id, {}), type: "rectangle", version };
}

/** The single message addressed to exactly `to` in a batch (asserts uniqueness). */
function only(batch: Outbound[], to: string): Message {
  const hits = batch.filter((o) => o.to.length === 1 && o.to[0] === to);
  expect(hits.length).toBe(1);
  return hits[0]!.message;
}

function join(core: RelayCore, connId: string, peer: Peer, room = "r1"): Outbound[] {
  core.connect(connId);
  return core.receive(connId, message("join", { protocol: 1, room, peer }));
}

describe("RelayCore — rooms & presence", () => {
  it("a joiner gets room-state with itself and the current scene", () => {
    const core = new RelayCore();
    const out = join(core, "c0", peerA);
    const state = only(out, "c0");
    expect(state.type).toBe("room-state");
    if (state.type !== "room-state") return;
    expect(state.you).toBe("A");
    expect(state.peers).toEqual([peerA]);
    expect(state.elements).toEqual([]);
  });

  it("a second join notifies the first peer and lists both", () => {
    const core = new RelayCore();
    join(core, "c0", peerA);
    const out = join(core, "c1", peerB);

    // c1 gets room-state listing both peers.
    const state = only(out, "c1");
    if (state.type !== "room-state") throw new Error("expected room-state");
    expect(state.peers.map((p) => p.id).sort()).toEqual(["A", "B"]);

    // c0 gets peer-joined for B.
    const joined = only(out, "c0");
    expect(joined).toEqual({ type: "peer-joined", peer: peerB });
  });

  it("disconnect broadcasts peer-left and drops the empty room", () => {
    const core = new RelayCore();
    join(core, "c0", peerA);
    join(core, "c1", peerB);
    const out = core.disconnect("c1");
    expect(only(out, "c0")).toEqual({ type: "peer-left", peerId: "B" });
    expect(core.peersIn("r1").map((p) => p.id)).toEqual(["A"]);

    core.disconnect("c0");
    expect(core.roomCount).toBe(0); // empty room cleaned up
  });

  it("a stale close does not evict a peer that already reconnected (regression)", () => {
    const core = new RelayCore();
    join(core, "c0", peerA);
    // peerA reconnects on a fresh connection (same id) before c0's close arrives.
    join(core, "c1", peerA);
    expect(core.peersIn("r1").map((p) => p.id)).toEqual(["A"]);
    // The old connection finally closes — must NOT remove the reconnected peer.
    const out = core.disconnect("c0");
    expect(out).toEqual([]);
    expect(core.peersIn("r1").map((p) => p.id)).toEqual(["A"]);
  });

  it("ping is answered with ack to the sender only", () => {
    const core = new RelayCore();
    core.connect("c0");
    const out = core.receive("c0", message("ping", { t: 42 }));
    expect(out).toEqual([{ to: ["c0"], message: { type: "ack", t: 42 } }]);
  });
});

describe("RelayCore — scene sync", () => {
  it("broadcasts element-updates to other peers and stores the snapshot", () => {
    const core = new RelayCore();
    join(core, "c0", peerA);
    join(core, "c1", peerB);

    const out = core.receive("c0", message("element-updates", { elements: [el("x", 1)] }));
    // Forwarded to c1 only (not the sender c0).
    expect(out.length).toBe(1);
    expect(out[0]!.to).toEqual(["c1"]);
    expect(out[0]!.message.type).toBe("element-updates");

    // A late joiner receives the stored scene.
    const late = join(core, "c2", { id: "C", name: "Cara", color: "#000" });
    const state = only(late, "c2");
    if (state.type !== "room-state") throw new Error("expected room-state");
    expect(state.elements.map((e) => e.id)).toEqual(["x"]);
  });

  it("reconciles the room snapshot — a stale update never overwrites a newer element", () => {
    const core = new RelayCore();
    join(core, "c0", peerA);
    core.receive("c0", message("element-updates", { elements: [el("x", 5)] }));
    core.receive("c0", message("element-updates", { elements: [el("x", 2)] })); // stale
    expect(core.sceneOf("r1").find((e) => e.id === "x")?.version).toBe(5);
  });

  it("presence and pointer go only to other peers", () => {
    const core = new RelayCore();
    join(core, "c0", peerA);
    join(core, "c1", peerB);

    const presence = core.receive(
      "c0",
      message("presence", {
        peerId: "A",
        presence: { pointer: { x: 1, y: 2 }, selectedIds: [], tool: "selection" },
      }),
    );
    expect(presence).toEqual([
      {
        to: ["c1"],
        message: {
          type: "presence",
          peerId: "A",
          presence: { pointer: { x: 1, y: 2 }, selectedIds: [], tool: "selection" },
        },
      },
    ]);

    const pointer = core.receive(
      "c0",
      message("pointer", { peerId: "A", pointer: { x: 9, y: 9 } }),
    );
    expect(pointer[0]!.to).toEqual(["c1"]);
  });

  it("a shared message before joining a room is ignored", () => {
    const core = new RelayCore();
    core.connect("c0");
    expect(core.receive("c0", message("element-updates", { elements: [el("x", 1)] }))).toEqual([]);
  });
});
