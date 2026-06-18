import { type RelayHandle, startRelay } from "@cyberdynecorp/excalidraw-relay";
import { type Page, expect, test } from "@playwright/test";
import { drag, read, ready } from "./helpers.js";

/**
 * Two browsers (simulated devices) join the same room through the real relay
 * and converge: one draws and the other sees it; presence rosters update both
 * ways. Mirrors the unit/integration coverage, but end-to-end in the browser.
 */
async function joinRoom(page: Page, port: number, room: string, name: string): Promise<void> {
  const relayUrl = `ws://127.0.0.1:${port}`;
  await page.goto(`/?relay=${encodeURIComponent(relayUrl)}&room=${room}&name=${name}`);
  await ready(page);
  await page.waitForFunction(() => {
    const store = (window as unknown as { __store?: { collab: { you: string | null } | null } }).__store;
    return store?.collab?.you != null;
  });
}

test("two browsers in one room converge on the same scene + presence", async ({ browser }) => {
  const relay: RelayHandle = startRelay(0);
  await new Promise<void>((resolve) => relay.wss.on("listening", resolve));
  const addr = relay.wss.address();
  const port = typeof addr === "object" && addr !== null ? addr.port : 0;

  const room = "e2e-room";
  const alice = await browser.newPage();
  const bob = await browser.newPage();
  await joinRoom(alice, port, room, "Alice");
  await joinRoom(bob, port, room, "Bob");

  // Each sees the other in the roster.
  await expect(alice.getByTestId("peers")).toContainText("Bob");
  await expect(bob.getByTestId("peers")).toContainText("Alice");

  // Alice draws a rectangle → Bob receives it via the relay.
  await alice.getByTestId("tool-rectangle").click();
  await drag(alice, { x: 0.3, y: 0.3 }, { x: 0.5, y: 0.5 });
  await bob.waitForFunction(() => {
    const store = (window as unknown as { __store?: { scene: { visibleElements: { type: string }[] } } }).__store;
    return store?.scene.visibleElements.some((e) => e.type === "rectangle") ?? false;
  });

  // Bob draws an ellipse → Alice receives it. Both scenes now match.
  await bob.getByTestId("tool-ellipse").click();
  await drag(bob, { x: 0.55, y: 0.3 }, { x: 0.75, y: 0.5 });
  await alice.waitForFunction(() => {
    const store = (window as unknown as { __store?: { scene: { visibleElements: { type: string }[] } } }).__store;
    return store?.scene.visibleElements.some((e) => e.type === "ellipse") ?? false;
  });

  const aliceTypes = await read(alice, (s) => s.scene.visibleElements.map((e) => e.type).sort());
  const bobTypes = await read(bob, (s) => s.scene.visibleElements.map((e) => e.type).sort());
  expect(aliceTypes).toEqual(["ellipse", "rectangle"]);
  expect(bobTypes).toEqual(["ellipse", "rectangle"]);

  await alice.screenshot({ path: "test-results/screens/14-collab-alice.png" });
  await alice.close();
  await bob.close();
  await relay.close();
});
