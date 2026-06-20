# Web Client Host

## Purpose

The Svelte 5 web shell that wraps the pure editor core for the browser — the
analogue of the iOS Platform UX layer. It covers the `Canvas` host's mouse/wheel
navigation, the right-click context menu over the canvas, and the host wiring
that keeps the on-canvas text editor visually consistent with the renderer. The
drawing, selection, rendering, and collaboration behaviours themselves are the
shared capability specs; this captures only the web-host-specific concerns.

## Requirements

### Requirement: Canvas navigation (wheel zoom, middle-mouse pan)

The web canvas SHALL zoom in/out on the mouse wheel, anchored at the cursor so
the scene point under the pointer stays fixed (`store.zoomAtScreenPoint`), and
SHALL pan the view while the middle mouse button is held and dragged, regardless
of the active tool. Shift+wheel SHALL pan horizontally. The right mouse button
SHALL NOT draw, select, or otherwise reach the editor — it is reserved for the
context menu. (src: web/apps/web/src/lib/Canvas.svelte, web/packages/excalidraw-svelte/src/svelte/editor-store.ts)

#### Scenario: Wheel zooms around the cursor
- GIVEN the canvas at 100% zoom with the cursor over a scene point
- WHEN the wheel is scrolled up then down
- THEN the zoom SHALL increase then decrease, and the scene point under the
  cursor SHALL remain fixed (src: web/apps/web/e2e/pan-zoom-contextmenu.spec.ts)

#### Scenario: Middle-mouse drag pans the canvas
- GIVEN the canvas with any active tool
- WHEN the middle mouse button is pressed and dragged
- THEN the viewport SHALL scroll with the drag and no element SHALL be created
  or selected (src: web/apps/web/e2e/pan-zoom-contextmenu.spec.ts)

#### Scenario: Right button does not disturb the selection
- GIVEN one or more selected elements
- WHEN the right mouse button is pressed on the canvas
- THEN the selection SHALL be preserved (the right button only opens the context
  menu) (src: web/apps/web/src/lib/Canvas.svelte)

### Requirement: Selection context menu

The web canvas SHALL open a context menu on right-click offering Duplicate,
Group, Ungroup, Bring to front, Send to back, Select all, and Delete. The
selection-dependent items SHALL be disabled when not applicable — Group only
with two or more selected elements, Ungroup only when the selection contains a
grouped element, and Duplicate/reorder/Delete only with a non-empty selection.
Choosing an item SHALL run the action and close the menu; clicking outside or
pressing Escape SHALL dismiss it. (src: web/apps/web/src/App.svelte, web/packages/excalidraw-svelte/src/svelte/editor-store.ts)

#### Scenario: Group, ungroup, and delete via the menu
- GIVEN two selected elements
- WHEN the user right-clicks and chooses Group
- THEN the elements SHALL be grouped, the menu SHALL close, and a subsequent
  right-click SHALL offer an enabled Ungroup; choosing Delete SHALL remove the
  selection (src: web/apps/web/e2e/pan-zoom-contextmenu.spec.ts)

#### Scenario: Menu items gate on the selection
- GIVEN no selection
- WHEN the context menu is shown
- THEN Group, Ungroup, Duplicate, reorder, and Delete SHALL be disabled while
  Select all remains available (src: web/apps/web/src/App.svelte)
