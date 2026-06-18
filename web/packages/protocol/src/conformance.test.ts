import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  type ExcalidrawElement,
  defaultBase,
  defaultTextProps,
} from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import { canonicalEncode, decode } from "./codec.js";
import { type Message, PROTOCOL_VERSION, type Peer } from "./messages.js";

/**
 * Cross-language wire conformance. These canonical (sorted-key) JSON fixtures are
 * the shared contract: the Swift client's `ExcalidrawCollabTests` decode the
 * *same* files and assert the same re-encoded bytes, so an iOS device and the
 * web client are guaranteed to speak byte-identical protocol frames. Regenerate
 * with `UPDATE_FIXTURES=1`.
 */
const DIR = join(process.cwd(), "..", "Fixtures", "protocol");
const UPDATE = process.env.UPDATE_FIXTURES === "1";

const peer: Peer = { id: "p1", name: "Leo", color: "#e64980" };

const rect: ExcalidrawElement = {
  ...defaultBase("el-1", {
    x: 20,
    y: 20,
    width: 120,
    height: 80,
    seed: 11,
    version: 3,
    versionNonce: 42,
  }),
  type: "rectangle",
};
const label: ExcalidrawElement = {
  ...defaultBase("el-2", {
    x: 40,
    y: 40,
    width: 60,
    height: 25,
    seed: 12,
    version: 1,
    versionNonce: 7,
  }),
  type: "text",
  ...defaultTextProps({ text: "hi", originalText: "hi" }),
};

const fixtures: Record<string, Message> = {
  join: { type: "join", protocol: PROTOCOL_VERSION, room: "room-1", peer },
  leave: { type: "leave", peerId: "p1" },
  "room-state": {
    type: "room-state",
    protocol: PROTOCOL_VERSION,
    you: "p1",
    peers: [peer],
    elements: [rect, label],
  },
  "peer-joined": { type: "peer-joined", peer },
  "peer-left": { type: "peer-left", peerId: "p1" },
  presence: {
    type: "presence",
    peerId: "p1",
    presence: { pointer: { x: 12.5, y: -3.25 }, selectedIds: ["el-1"], tool: "selection" },
  },
  pointer: { type: "pointer", peerId: "p1", pointer: { x: 1, y: 2 } },
  "element-updates": { type: "element-updates", elements: [rect] },
  "scene-snapshot": { type: "scene-snapshot", elements: [rect, label] },
  ping: { type: "ping", t: 1700000000000 },
  ack: { type: "ack", t: 1700000000000 },
};

describe("protocol wire conformance (shared with the Swift client)", () => {
  for (const [name, msg] of Object.entries(fixtures)) {
    it(`${name}: canonical encoding matches the committed fixture`, () => {
      const path = join(DIR, `${name}.json`);
      const wire = canonicalEncode(msg);
      if (UPDATE) {
        mkdirSync(DIR, { recursive: true });
        writeFileSync(path, `${wire}\n`);
        return;
      }
      expect(existsSync(path), `missing fixture ${name}.json (run UPDATE_FIXTURES=1)`).toBe(true);
      expect(wire).toBe(readFileSync(path, "utf8").trim());
    });

    it(`${name}: decodes from the fixture and re-encodes identically`, () => {
      const path = join(DIR, `${name}.json`);
      if (!existsSync(path)) return; // generated in the test above when UPDATE=1
      const fixture = readFileSync(path, "utf8").trim();
      const round = canonicalEncode(decode(fixture));
      expect(round).toBe(fixture);
    });
  }
});
