import { type Message, decode, encode } from "@cyberdynecorp/excalidraw-protocol";
import { type WebSocket, WebSocketServer } from "ws";
import { type Outbound, RelayCore } from "./relay-core.js";

export interface RelayHandle {
  /** The underlying ws server (its `address()` gives the bound port). */
  wss: WebSocketServer;
  core: RelayCore;
  close(): Promise<void>;
}

/**
 * Start the collaboration relay on `port` (use 0 for an ephemeral port in
 * tests). A raw WebSocket server: every frame is a JSON `@cyberdynecorp/excalidraw-protocol` message;
 * malformed frames are dropped, valid ones are handed to {@link RelayCore} and
 * its {@link Outbound} batches are fanned out to the addressed connections.
 */
export function startRelay(port = 3001): RelayHandle {
  const wss = new WebSocketServer({ port });
  const core = new RelayCore();
  const sockets = new Map<string, WebSocket>();
  let nextId = 0;

  const dispatch = (batch: Outbound[]): void => {
    for (const out of batch) {
      const data = encode(out.message);
      for (const connId of out.to) sockets.get(connId)?.send(data);
    }
  };

  wss.on("connection", (socket) => {
    const connId = `c${nextId++}`;
    sockets.set(connId, socket);
    core.connect(connId);

    socket.on("message", (raw) => {
      let message: Message;
      try {
        message = decode(raw.toString());
      } catch {
        return; // ignore malformed frames
      }
      dispatch(core.receive(connId, message));
    });

    socket.on("close", () => {
      dispatch(core.disconnect(connId));
      sockets.delete(connId);
    });
    socket.on("error", () => socket.close());
  });

  return {
    wss,
    core,
    close: () =>
      new Promise<void>((resolve) => {
        for (const socket of sockets.values()) socket.terminate();
        wss.close(() => resolve());
      }),
  };
}
