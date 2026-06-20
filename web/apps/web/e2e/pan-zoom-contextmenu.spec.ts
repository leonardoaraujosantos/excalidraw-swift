import { expect, test } from "@playwright/test";
import { clickCanvas, drag, elementCount, read, ready, selectedCount, selectTool } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  await ready(page);
});

/** Centre of the canvas in client coordinates. */
async function canvasCentre(page: import("@playwright/test").Page): Promise<{ x: number; y: number }> {
  const box = await page.getByTestId("canvas").boundingBox();
  if (box === null) throw new Error("canvas not found");
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

test("the mouse wheel zooms in and out around the cursor", async ({ page }) => {
  expect(await read(page, (s) => s.zoomPercent)).toBe(100);
  const c = await canvasCentre(page);
  await page.mouse.move(c.x, c.y);

  await page.mouse.wheel(0, -120); // wheel up → zoom in
  expect(await read(page, (s) => s.zoomPercent)).toBeGreaterThan(100);

  await page.mouse.wheel(0, 120); // wheel down → zoom out
  expect(await read(page, (s) => s.zoomPercent)).toBeLessThanOrEqual(100);
});

test("the middle mouse button pans the canvas", async ({ page }) => {
  expect(await read(page, (s) => s.viewport.scrollX)).toBeCloseTo(0, 6);
  const c = await canvasCentre(page);

  await page.mouse.move(c.x, c.y);
  await page.mouse.down({ button: "middle" });
  await page.mouse.move(c.x + 140, c.y + 90, { steps: 5 });
  await page.mouse.up({ button: "middle" });

  // Dragging right/down with the middle button scrolls the content with it.
  expect(await read(page, (s) => s.viewport.scrollX)).toBeGreaterThan(50);
  expect(await read(page, (s) => s.viewport.scrollY)).toBeGreaterThan(30);
});

test("right-click opens a context menu to group, ungroup, and delete a selection", async ({ page }) => {
  await selectTool(page, "rectangle");
  await drag(page, { x: 0.2, y: 0.3 }, { x: 0.4, y: 0.5 });
  await selectTool(page, "rectangle");
  await drag(page, { x: 0.55, y: 0.3 }, { x: 0.75, y: 0.5 });
  await selectTool(page, "selection");
  await drag(page, { x: 0.1, y: 0.15 }, { x: 0.9, y: 0.7 });
  expect(await selectedCount(page)).toBe(2);

  const menu = page.getByTestId("context-menu");
  const c = await canvasCentre(page);

  // Group via the context menu.
  await page.mouse.click(c.x, c.y, { button: "right" });
  await expect(menu).toBeVisible();
  await expect(page.getByTestId("ctx-group")).toBeEnabled();
  await page.getByTestId("ctx-group").click();
  await expect(menu).toBeHidden();

  // The group is now ungroupable, and Escape dismisses the menu.
  await page.mouse.click(c.x, c.y, { button: "right" });
  await expect(page.getByTestId("ctx-ungroup")).toBeEnabled();
  await page.keyboard.press("Escape");
  await expect(menu).toBeHidden();

  // Delete the selection via the context menu.
  await page.mouse.click(c.x, c.y, { button: "right" });
  await page.getByTestId("ctx-delete").click();
  expect(await elementCount(page)).toBe(0);
});

test("a text element's box matches its rendered glyphs (not a monospace guess)", async ({ page }) => {
  await selectTool(page, "text");
  await clickCanvas(page, { x: 0.3, y: 0.4 });
  const editor = page.getByTestId("text-editor");
  await expect(editor).toBeVisible();
  await editor.fill("Hi Hello Everyone");
  await editor.press("Enter");

  const el = await read(page, (s) => {
    const t = s.scene.visibleElements.find((e) => e.type === "text") as
      | { width: number; fontSize: number; text: string }
      | undefined;
    return t ? { width: t.width, fontSize: t.fontSize, text: t.text } : null;
  });
  expect(el).not.toBeNull();
  if (el === null) return;

  // The stored width is the glyph width in the actual render font…
  const measured = await page.evaluate(({ text, fontSize }) => {
    const ctx = document.createElement("canvas").getContext("2d");
    if (ctx === null) return 0;
    ctx.font = `${fontSize}px "Excalifont", "Virgil", "Bradley Hand", "Comic Sans MS", "Segoe Print", cursive`;
    return ctx.measureText(text).width;
  }, el);
  expect(el.width).toBeCloseTo(measured, 0);
  // …and therefore differs from the old charCount·fontSize·0.6 monospace guess.
  expect(Math.abs(el.width - el.text.length * el.fontSize * 0.6)).toBeGreaterThan(1);
});
