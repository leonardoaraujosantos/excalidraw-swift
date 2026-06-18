import { canonicalJSON } from "@cyberdynecorp/excalidraw-model";
import { MESSAGE_TYPES, type Message, type MessageType } from "./messages.js";

const TYPES = new Set<string>(MESSAGE_TYPES);

/** Thrown by {@link decode} on malformed or unknown wire data. */
export class ProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProtocolError";
  }
}

/** Whether `value` looks like a protocol message (has a known `type` tag). */
export function isMessage(value: unknown): value is Message {
  return (
    typeof value === "object" &&
    value !== null &&
    "type" in value &&
    typeof (value as { type: unknown }).type === "string" &&
    TYPES.has((value as { type: string }).type)
  );
}

/** Serialize a message to a JSON wire string (v1 transport is JSON). */
export function encode(message: Message): string {
  return JSON.stringify(message);
}

/**
 * Canonical wire encoding: compact JSON with recursively sorted keys, matching
 * Swift's `JSONEncoder` (`.sortedKeys` + `.withoutEscapingSlashes`). Both clients
 * produce byte-identical output for the same message, so it is the format used
 * for the shared cross-language conformance fixtures. The live transport can use
 * the faster {@link encode}; a decoder accepts either (JSON parse ignores order).
 */
export function canonicalEncode(message: Message): string {
  return canonicalJSON(message, false);
}

/**
 * Parse and validate a wire string into a {@link Message}. Throws
 * {@link ProtocolError} on invalid JSON or an unrecognized `type` so the relay
 * and clients can reject garbage instead of acting on it.
 */
export function decode(data: string): Message {
  let parsed: unknown;
  try {
    parsed = JSON.parse(data);
  } catch (cause) {
    throw new ProtocolError(`invalid JSON: ${(cause as Error).message}`);
  }
  if (!isMessage(parsed)) {
    const tag =
      typeof parsed === "object" && parsed !== null && "type" in parsed
        ? String((parsed as { type: unknown }).type)
        : typeof parsed;
    throw new ProtocolError(`unknown message type: ${tag}`);
  }
  return parsed;
}

/** Type-safe message constructor (handy for tests and clients). */
export function message<T extends MessageType>(
  type: T,
  rest: Omit<Extract<Message, { type: T }>, "type">,
): Extract<Message, { type: T }> {
  return { type, ...rest } as Extract<Message, { type: T }>;
}
