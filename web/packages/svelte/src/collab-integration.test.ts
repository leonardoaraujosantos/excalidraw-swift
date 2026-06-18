import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { encode, message, reconcileElements } from "@cyberdynecorp/excalidraw-protocol";
import { type RelayHandle, startRelay } from "@cyberdynecorp/excalidraw-relay";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { CollabSession, type CollabSocket, reconnectingSocket } from "./collab-session.js";

/**
 * End-to-end collaboration over the real relay with *simulated devices*: a
 * `CollabSession` for the web client and another for the "iOS" client, plus a
 * raw-protocol client (no `CollabSession`) standing in for the minimal Swift
 * client. They share one room and converge on the same scene.
 */
let relay: RelayHandle;
let url: string;

beforeEach(async () => {
  relay = startRelay(0);
  await new Promise<void>((resolve) => relay.wss.on("listening", resolve));
  const addr = relay.wss.address();
  url = `ws://127.0.0.1:${typeof addr === "object" && addr !== null ? addr.port : 0}`;
});

afterEach(async () => {
  await relay.close();
});

function wsSocket(ws: WebSocket): CollabSocket {
  ws.on("error", () => {}); // swallow connect failures (treated as a close → reconnect)
  return {
    send: (d) => {
      if (ws.readyState === ws.OPEN) ws.send(d);
    },
    close: () => ws.close(),
    onOpen: (h) => ws.on("open", h),
    onMessage: (h) => ws.on("message", (raw) => h(raw.toString())),
    onClose: (h) => ws.on("close", () => h()),
  };
}

function el(id: string, version = 1): ExcalidrawElement {
  return { ...defaultBase(id, {}), type: "rectangle", version };
}

/** A device backed by a CollabSession whose scene mirrors the room. */
function device(name: string) {
  const scene = new Map<string, ExcalidrawElement>();
  const ws = new WebSocket(url);
  const session = new CollabSession(wsSocket(ws), { id: name, name, color: "#000" }, "room", {
    onScene: (els) => {
      scene.clear();
      for (const e of els) scene.set(e.id, e);
    },
    onRemoteElements: (els) => {
      // Mirror EditorStore.applyRemoteElements: reconcile, don't overwrite.
      const merged = reconcileElements([...scene.values()], els);
      scene.clear();
      for (const e of merged) scene.set(e.id, e);
    },
  });
  // A local edit updates this device's scene, then broadcasts (the relay never
  // echoes to the sender, so the local copy must be applied here).
  const edit = (elements: ExcalidrawElement[]): void => {
    for (const e of elements) scene.set(e.id, e);
    session.broadcastElements(elements);
  };
  return { session, scene, ws, edit };
}

async function until(predicate: () => boolean, timeout = 5000): Promise<void> {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeout) throw new Error("condition timed out");
    await new Promise((r) => setTimeout(r, 10));
  }
}

describe("collaboration end-to-end (simulated devices)", () => {
  it("two CollabSession devices converge on the same scene", async () => {
    const web = device("web");
    const ios = device("ios");
    await until(() => web.session.you !== null && ios.session.you !== null);

    // web draws → ios receives it.
    web.edit([el("rect-web", 1)]);
    await until(() => ios.scene.has("rect-web"));

    // ios draws → web receives it.
    ios.edit([el("rect-ios", 1)]);
    await until(() => web.scene.has("rect-ios"));

    // Both see both elements — and see each other in the roster.
    expect([...web.scene.keys()].sort()).toEqual(["rect-ios", "rect-web"]);
    expect([...ios.scene.keys()].sort()).toEqual(["rect-ios", "rect-web"]);
    expect(web.session.peers.has("ios")).toBe(true);
    expect(ios.session.peers.has("web")).toBe(true);

    web.ws.close();
    ios.ws.close();
  });

  it("a stale edit loses to a newer one on both peers (reconcile)", async () => {
    const web = device("web");
    const ios = device("ios");
    await until(() => web.session.you !== null && ios.session.you !== null);

    web.edit([el("shared", 5)]);
    await until(() => ios.scene.get("shared")?.version === 5);

    // A stale (older) frame arrives late → it must not win on the peer.
    ios.session.broadcastElements([el("shared", 2)]);
    await new Promise((r) => setTimeout(r, 50));
    // web reconciles the incoming v2 against its v5 and keeps v5.
    expect(web.scene.get("shared")?.version).toBe(5);
    expect(ios.scene.get("shared")?.version).toBe(5);

    web.ws.close();
    ios.ws.close();
  });

  it("survives a dropped socket: reconnects, rejoins, and resyncs the scene", async () => {
    // Another device seeds the room.
    const other = device("seed");
    await until(() => other.session.you !== null);
    other.edit([el("seeded", 1)]);

    // A reconnecting client whose underlying sockets we can drop.
    const raws: WebSocket[] = [];
    const scene = new Map<string, ExcalidrawElement>();
    const session = new CollabSession(
      reconnectingSocket(
        () => {
          const ws = new WebSocket(url);
          raws.push(ws);
          return wsSocket(ws);
        },
        { schedule: (_attempt, run) => setTimeout(run, 20) },
      ),
      { id: "rejoiner", name: "Re", color: "#000" },
      "room",
      {
        onScene: (els) => {
          scene.clear();
          for (const e of els) scene.set(e.id, e);
        },
        onRemoteElements: (els) => {
          for (const e of els) scene.set(e.id, e);
        },
      },
    );
    await until(() => session.you !== null && scene.has("seeded"));

    // Force-drop the live socket; the wrapper must redial and rejoin.
    raws[0]!.close();
    await until(() => raws.length >= 2 && session.you !== null);
    // After rejoining, the relay re-sends the room scene (still has "seeded").
    await until(() => scene.has("seeded"));
    expect(session.you).toBe("rejoiner");

    session.leave();
    other.ws.close();
  });

  it("a raw-protocol client (the minimal Swift client) interoperates", async () => {
    const web = device("web");
    await until(() => web.session.you !== null);

    // A bare ws client that speaks @cyberdynecorp/excalidraw-protocol directly — no CollabSession.
    const raw = new WebSocket(url);
    await new Promise<void>((resolve) => raw.on("open", () => resolve()));
    raw.send(
      encode(
        message("join", {
          protocol: 1,
          room: "room",
          peer: { id: "swift", name: "iPad", color: "#a00" },
        }),
      ),
    );
    raw.send(encode(message("element-updates", { elements: [el("from-swift", 1)] })));

    await until(() => web.scene.has("from-swift"));
    expect(web.session.peers.has("swift")).toBe(true);

    raw.close();
    web.ws.close();
  });
});
