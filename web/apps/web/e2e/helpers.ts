import { expect, type Page } from "@playwright/test";

/** A read-only view of the app's editor store exposed on `window.__store`. */
interface StoreView {
  scene: {
    visibleElements: {
      type: string;
      text?: string;
      width: number;
      height: number;
      backgroundColor: string;
    }[];
  };
  controller: { selectedIDs: { size: number } };
  trail: { laser: unknown[]; eraser: unknown[] };
  theme: string;
  zoomPercent: number;
  viewport: { scrollX: number; scrollY: number; zoom: number };
}

/** Read a derived value out of the live editor store. */
export function read<T>(page: Page, fn: (s: StoreView) => T): Promise<T> {
  return page.evaluate(
    ([f]) => {
      const store = (window as unknown as { __store: StoreView }).__store;
      // biome-ignore lint: evaluated in the browser
      return new Function("s", `return (${f})(s)`)(store) as never;
    },
    [fn.toString()] as const,
  );
}

export const elementCount = (page: Page) => read(page, (s) => s.scene.visibleElements.length);
export const selectedCount = (page: Page) => read(page, (s) => s.controller.selectedIDs.size);

export async function selectTool(page: Page, tool: string): Promise<void> {
  await page.getByTestId(`tool-${tool}`).click();
}

interface Frac {
  x: number;
  y: number;
}

async function abs(page: Page, f: Frac): Promise<{ x: number; y: number }> {
  const box = await page.getByTestId("canvas").boundingBox();
  if (box === null) throw new Error("canvas not found");
  return { x: box.x + box.width * f.x, y: box.y + box.height * f.y };
}

/** Drag on the canvas between two fractional points (0–1 of the canvas box). */
export async function drag(page: Page, from: Frac, to: Frac): Promise<void> {
  const a = await abs(page, from);
  const b = await abs(page, to);
  await page.mouse.move(a.x, a.y);
  await page.mouse.down();
  await page.mouse.move((a.x + b.x) / 2, (a.y + b.y) / 2, { steps: 5 });
  await page.mouse.move(b.x, b.y, { steps: 5 });
  await page.mouse.up();
}

export async function clickCanvas(page: Page, at: Frac): Promise<void> {
  const p = await abs(page, at);
  await page.mouse.move(p.x, p.y);
  await page.mouse.down();
  await page.mouse.up();
}

export async function shot(page: Page, name: string): Promise<void> {
  await page.screenshot({ path: `test-results/screens/${name}.png` });
}

/** Wait until the canvas is present and the store is exposed. */
export async function ready(page: Page): Promise<void> {
  await expect(page.getByTestId("canvas")).toBeVisible();
  await page.waitForFunction(() => (window as unknown as { __store?: unknown }).__store !== undefined);
}
