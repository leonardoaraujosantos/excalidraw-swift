import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { ProtocolError, decode, encode, isMessage, message } from "./codec.js";
import { type Message, PROTOCOL_VERSION } from "./messages.js";

const rect: ExcalidrawElement = {
  ...defaultBase("a", { width: 10, height: 10 }),
  type: "rectangle",
};
const peer = { id: "p1", name: "Leo", color: "#e64980" };

const samples: Message[] = [
  message("join", { protocol: PROTOCOL_VERSION, room: "r1", peer }),
  message("leave", { peerId: "p1" }),
  message("room-state", { protocol: PROTOCOL_VERSION, you: "p1", peers: [peer], elements: [rect] }),
  message("peer-joined", { peer }),
  message("peer-left", { peerId: "p1" }),
  message("presence", {
    peerId: "p1",
    presence: { pointer: { x: 1, y: 2 }, selectedIds: ["a"], tool: "selection" },
  }),
  message("pointer", { peerId: "p1", pointer: { x: 3, y: 4 } }),
  message("element-updates", { elements: [rect] }),
  message("scene-snapshot", { elements: [rect] }),
  message("ping", { t: 123 }),
  message("ack", { t: 123 }),
];

describe("codec", () => {
  it("round-trips every message type", () => {
    for (const msg of samples) {
      const back = decode(encode(msg));
      expect(back).toEqual(msg);
      expect(isMessage(back)).toBe(true);
    }
  });

  it("preserves element version/versionNonce across the wire (reconcile inputs)", () => {
    const msg = message("element-updates", {
      elements: [{ ...rect, version: 7, versionNonce: 4242 }],
    });
    const back = decode(encode(msg));
    if (back.type !== "element-updates") throw new Error("wrong type");
    expect(back.elements[0]?.version).toBe(7);
    expect(back.elements[0]?.versionNonce).toBe(4242);
  });

  it("rejects invalid JSON", () => {
    expect(() => decode("{not json")).toThrow(ProtocolError);
  });

  it("rejects an unknown message type", () => {
    expect(() => decode(JSON.stringify({ type: "explode" }))).toThrow(
      /unknown message type: explode/,
    );
  });

  it("isMessage guards non-messages", () => {
    expect(isMessage({ type: "join" })).toBe(true);
    expect(isMessage({ type: "nope" })).toBe(false);
    expect(isMessage(null)).toBe(false);
    expect(isMessage("ping")).toBe(false);
  });
});
