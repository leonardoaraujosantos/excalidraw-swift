export { RelayCore, type Outbound } from "./relay-core.js";
export { startRelay, type RelayHandle } from "./server.js";

// Run directly (`node server/src/index.ts` via tsx, or the built dist) to start
// a relay. PORT env overrides the default 3001.
import { startRelay } from "./server.js";

const isMain = typeof process !== "undefined" && import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  const port = Number(process.env.PORT ?? 3001);
  const { wss } = startRelay(port);
  wss.on("listening", () => console.log(`relay listening on :${port}`));
}
