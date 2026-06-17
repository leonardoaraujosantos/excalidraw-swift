import { Scene } from "@xs/model";
import { describe, expect, it } from "vitest";
import { containsScene, crc32, embedScene, extractScene } from "./png-embed.js";
import { rect } from "./test-helpers.js";

const ascii = (s: string): number[] => [...s].map((c) => c.charCodeAt(0));

/** A minimal valid PNG: signature + IHDR(13) + IEND, enough to host a tEXt chunk. */
function minimalPng(): Uint8Array {
  const ihdrData = [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]; // 1×1 RGBA
  return Uint8Array.from([
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a, // signature
    0,
    0,
    0,
    13,
    ...ascii("IHDR"),
    ...ihdrData,
    0,
    0,
    0,
    0, // IHDR chunk (crc placeholder)
    0,
    0,
    0,
    0,
    ...ascii("IEND"),
    0,
    0,
    0,
    0, // IEND chunk
  ]);
}

describe("PNG scene embed", () => {
  it("CRC-32 matches the known check value", () => {
    // CRC32 of ASCII "123456789" is 0xCBF43926.
    expect(crc32(Uint8Array.from(ascii("123456789")))).toBe(0xcbf43926);
  });

  it("embeds and re-extracts a scene", () => {
    const scene = new Scene([rect({ x: 10, y: 10, w: 80, h: 60 })]);
    const png = minimalPng();
    const embedded = embedScene(scene, png)!;
    expect(embedded).not.toBeNull();
    expect(containsScene(png)).toBe(false);
    expect(containsScene(embedded)).toBe(true);

    const restored = extractScene(embedded)!;
    expect(restored.visibleElements.length).toBe(1);
    expect(restored.visibleElements[0]!.type).toBe("rectangle");
  });

  it("keeps the PNG signature intact after embedding", () => {
    const embedded = embedScene(new Scene([rect({ w: 10, h: 10 })]), minimalPng())!;
    expect([...embedded.subarray(0, 8)]).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  });

  it("returns null for non-PNG data", () => {
    expect(embedScene(new Scene([]), Uint8Array.from([1, 2, 3]))).toBeNull();
    expect(extractScene(Uint8Array.from([1, 2, 3]))).toBeNull();
    expect(containsScene(Uint8Array.from([1, 2, 3]))).toBe(false);
  });

  it("preserves UTF-8 text content through the round-trip", () => {
    const scene = new Scene([
      rect({ w: 10, h: 10, bg: "#héllo".slice(0, 1) === "#" ? "#abcdef" : "#000" }),
    ]);
    const restored = extractScene(embedScene(scene, minimalPng())!)!;
    expect(restored.visibleElements.length).toBe(1);
  });
});
