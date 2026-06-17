import { type Scene, SceneDocument } from "@xs/model";

const KEYWORD = "excalidraw";
const SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const crcTable: number[] = (() => {
  const table = new Array<number>(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = (c & 1) !== 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[i] = c >>> 0;
  }
  return table;
})();

/** Standard PNG/zlib CRC-32 (polynomial 0xEDB88320). (parity: CRC32) */
export function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 0xff]! ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function hasSignature(data: Uint8Array): boolean {
  if (data.length < 8) return false;
  return SIGNATURE.every((b, i) => data[i] === b);
}

function uint32(value: number): number[] {
  return [(value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff];
}

function bytesToBinary(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return s;
}

function binaryToBytes(s: string): Uint8Array {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

function makeChunk(type: string, data: number[]): number[] {
  const typeBytes = [...type].map((c) => c.charCodeAt(0));
  const payload = [...typeBytes, ...data];
  return [...uint32(data.length), ...payload, ...uint32(crc32(Uint8Array.from(payload)))];
}

/**
 * Embed `scene` into PNG bytes, returning new bytes (or `null` if the input
 * isn't a PNG). The scene JSON is base64-encoded into a `tEXt` chunk keyed
 * `excalidraw`, inserted right after `IHDR`. (parity: PNGSceneEmbed.swift)
 */
export function embedScene(scene: Scene, png: Uint8Array): Uint8Array | null {
  if (!hasSignature(png) || png.length < 8 + 25) return null;
  const json = SceneDocument.encode(scene, "excalidraw-web", false);
  const base64 = btoa(bytesToBinary(new TextEncoder().encode(json)));
  const text = [
    ...[...KEYWORD].map((c) => c.charCodeAt(0)),
    0,
    ...[...base64].map((c) => c.charCodeAt(0)),
  ];
  const chunk = makeChunk("tEXt", text);

  const insertAt = 8 + 25; // signature(8) + IHDR(25)
  const out = new Uint8Array(png.length + chunk.length);
  out.set(png.subarray(0, insertAt), 0);
  out.set(Uint8Array.from(chunk), insertAt);
  out.set(png.subarray(insertAt), insertAt + chunk.length);
  return out;
}

function extractText(png: Uint8Array): string | null {
  if (!hasSignature(png)) return null;
  let offset = 8;
  while (offset + 8 <= png.length) {
    const length =
      (png[offset]! << 24) | (png[offset + 1]! << 16) | (png[offset + 2]! << 8) | png[offset + 3]!;
    const typeStart = offset + 4;
    if (typeStart + 4 > png.length) return null;
    const type = String.fromCharCode(...png.subarray(typeStart, typeStart + 4));
    const dataStart = typeStart + 4;
    if (dataStart + length + 4 > png.length) return null;
    if (type === "tEXt") {
      const chunk = png.subarray(dataStart, dataStart + length);
      const nul = chunk.indexOf(0);
      if (nul !== -1 && String.fromCharCode(...chunk.subarray(0, nul)) === KEYWORD) {
        return String.fromCharCode(...chunk.subarray(nul + 1));
      }
    }
    if (type === "IEND") return null;
    offset = dataStart + length + 4;
  }
  return null;
}

/** Extract an embedded scene from PNG bytes, or `null` when there's none. */
export function extractScene(png: Uint8Array): Scene | null {
  const base64 = extractText(png);
  if (base64 === null) return null;
  try {
    const json = new TextDecoder().decode(binaryToBytes(atob(base64)));
    return SceneDocument.decode(json);
  } catch {
    return null;
  }
}

/** Whether `png` carries an embedded scene. */
export function containsScene(png: Uint8Array): boolean {
  return extractText(png) !== null;
}
