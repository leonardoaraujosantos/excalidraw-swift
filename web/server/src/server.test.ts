import { type Message, decode, encode, message } from "@xs/protocol";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { type RelayHandle, startRelay } from "./server.js";

let relay: RelayHandle;
let url: string;

beforeEach(async () => {
  relay = startRelay(0); // ephemeral port
  await new Promise<void>((resolve) => relay.wss.on("listening", resolve));
  const addr = relay.wss.address();
  const port = typeof addr === "object" && addr !== null ? addr.port : 0;
  url = `ws://127.0.0.1:${port}`;
});

afterEach(async () => {
  await relay.close();
});

/** Open a client socket and resolve once it is connected. */
function open(): Promise<WebSocket> {
  const ws = new WebSocket(url);
  return new Promise((resolve, reject) => {
    ws.on("open", () => resolve(ws));
    ws.on("error", reject);
  });
}

/** Resolve with the next decoded message on `ws`. */
function next(ws: WebSocket): Promise<Message> {
  return new Promise((resolve) => ws.once("message", (raw) => resolve(decode(raw.toString()))));
}

function send(ws: WebSocket, msg: Message): void {
  ws.send(encode(msg));
}

describe("relay server (end-to-end over ws)", () => {
  it("delivers room-state, peer-joined, and element-updates between two clients", async () => {
    const a = await open();
    send(
      a,
      message("join", { protocol: 1, room: "room", peer: { id: "A", name: "A", color: "#111" } }),
    );
    const stateA = await next(a);
    expect(stateA.type).toBe("room-state");

    const b = await open();
    const bJoined = next(a); // A should be told B joined
    send(
      b,
      message("join", { protocol: 1, room: "room", peer: { id: "B", name: "B", color: "#222" } }),
    );
    const stateB = await next(b);
    expect(stateB.type).toBe("room-state");
    expect((await bJoined).type).toBe("peer-joined");

    // A edits → B receives the element-update.
    const bUpdate = next(b);
    send(a, message("element-updates", { elements: [{ id: "x" } as never] }));
    const got = await bUpdate;
    expect(got.type).toBe("element-updates");
    if (got.type === "element-updates") expect(got.elements[0]?.id).toBe("x");

    a.close();
    b.close();
  });

  it("ignores malformed frames without dropping the connection", async () => {
    const a = await open();
    a.send("not json at all");
    // The socket stays open and still works: a ping is answered.
    send(a, message("ping", { t: 7 }));
    const ack = await next(a);
    expect(ack).toEqual({ type: "ack", t: 7 });
    a.close();
  });
});
