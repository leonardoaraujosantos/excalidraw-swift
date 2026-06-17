# excalidraw-web — TypeScript + Svelte 5 twin

The web implementation of the Excalidraw library, a twin of the Swift app under
`../Sources`. Both are built against the language-neutral [OpenSpec
specs](../openspec/specs/) and share golden fixtures so they can't drift. See
[docs/TYPESCRIPT_SVELTE_PORT.md](../docs/TYPESCRIPT_SVELTE_PORT.md) for the full
roadmap.

## Layout

```
web/
├── packages/
│   ├── math/      @xs/math — points, vectors, angles, curves, geometry  ✅ T0
│   ├── model/     @xs/model — element schema, scene, .excalidraw codecs ✅ T1
│   ├── geometry/  @xs/geometry — bounds, hit-test, snapping, elbow A*  ✅ T2
│   ├── render/    @xs/render — Canvas2D renderer, rough.js, SVG/PNG     🟡 T3
│   ├── editor/    @xs/editor — tools, selection, generators, smart     ✅ T4
│   ├── svelte/    @xs/svelte — reactive EditorStore + Svelte bridge   🟡 T5
│   └── protocol/  @xs/protocol — collaboration wire schema               (T7)
├── apps/web/      browser app (Vite + Svelte 5)                         🟡 T5
└── server/        WebSocket relay                                         (T7)
```

## Develop

Requires Node ≥ 20.19 and pnpm 10.

```sh
pnpm install
pnpm test          # vitest across all packages
pnpm typecheck     # tsc --noEmit per package
pnpm lint          # biome

# End-to-end (drives the real app in a browser, like the iOS SmokeUITests):
pnpm --filter excalidraw-web-app exec playwright install chromium   # once
pnpm --filter excalidraw-web-app e2e                                # screenshots → apps/web/test-results/screens/
```

## Status

- **T0 — Foundations:** `@xs/math` ported from `ExcalidrawMath` with the Swift
  unit tests ported to Vitest (67 tests). Strict TS (`noUncheckedIndexedAccess`).
- **T1 — Model & file format:** `@xs/model` ported from `ExcalidrawModel` — the
  flat element schema (13 types), `Scene` with versioned `mutate`, diff-based
  `History`/`Store` undo-redo, `restore` + fractional indexing, and the
  `.excalidraw` / `.excalidrawlib` codecs with canonical (sorted-key) JSON.
  39 tests, including a **cross-language round-trip** that reads the shared
  `../Fixtures/*.excalidraw` and asserts the re-encode is semantically
  diff-clean against the Swift-authored source.
- **T2 — Geometry (in progress):** `@xs/geometry` ported from
  `ExcalidrawGeometry` — `BoundingBox`, rotation-aware element bounds + outline
  extraction, hit-testing (`shouldTestInside`/`hit`/`distance`), arrow binding,
  cardinal `Heading`s, viewport culling, dirty regions, frame containment,
  object + gap snapping, and the Snap-to-Shape `ShapeGenerator`. 48 tests.
  Still to port: the elbow-arrow A\* router and the freehand shape recognizer.
- **T3 — Rendering (in progress):** `@xs/render` ported from `ExcalidrawRender`
  — `Viewport`, rough.js option builder + element drawables (via the real
  `roughjs`), op-set → SVG-path / canvas-path serialization, a Canvas2D
  `renderScene` (drawables, perfect-freehand freedraw, text, frames, viewport
  culling), full **SVG export**, and **PNG scene-embed** round-trip
  (`tEXt` chunk + CRC-32). 27 tests, incl. the renderer verified against a
  recording mock 2D context. Still to port: the interactive overlay and the
  PNG rasterizer (needs a real/headless canvas).
- **T4 — Editor engine (in progress):** `@xs/editor` ported from
  `ExcalidrawEditor` — the pure pointer state machine: tool model, element
  creation (shapes/line/arrow/freedraw/frame), single/group/box/multi
  selection, move/resize/rotate (with aspect + from-centre), eraser, undo/redo,
  and the selection actions (group/ungroup, duplicate, lock, z-order,
  align, flip) + object/gap snapping + frame membership. 40 tests ported from
  the Swift editor suite. Still to port: arrow binding, elbow arrows, linear
  point edit, image crop, generators (mermaid/tables/charts/sticky-notes),
  shape recognition, flowchart spawning, hyperlinks, copy-paste.
  - **T4 slice 2:** generators (sticky notes, tables, charts), text
    create/edit, element links, copy/paste, image/embeddable/library insert.
    23 more tests (ported from StickyNote/Table/Chart/ElementLink/CopyPaste).
    Still to port: arrow binding, elbow arrows, linear point edit, image crop,
    Mermaid parser, shape recognition, flowchart spawning.
  - **T4 slice 3:** Mermaid flowchart parser (`parseMermaid` + `insertMermaid`)
    — node shapes `[rect] (rounded) {diamond} ((circle)) ([stadium])`, edges
    `--> --- -.-> ==>` with `|labels|`, longest-path layering by direction,
    bound-text labels + bound arrows. 7 tests ported from MermaidParserTests.
    Still to port: arrow binding, elbow arrows, linear point edit, image crop,
    shape recognition, flowchart spawning.
  - **T4 slice 4:** freehand shape recognition (`ShapeRecognizer` in
    `@xs/geometry` + `recognizeFreedraw`) — RDP simplification + circularity +
    star/heart/cloud/speech-bubble feature detectors → snap a stroke to a clean
    rectangle/ellipse/diamond/triangle/pentagon/hexagon/star/etc. 5 tests
    ported from ShapeRecognitionTests. Still to port: arrow binding, elbow
    arrows, linear point edit, image-crop drag, flowchart spawning.
  - **T4 slice 5:** arrow↔shape binding — bind an arrow's endpoints to nearby
    bindable shapes on creation, register the arrow in the shape's
    `boundElements`, and re-route bound arrows when their targets move/resize.
    3 tests ported from BindingTests. Still to port: elbow arrows, linear point
    edit, image-crop drag, flowchart spawning.
  - **T4 slice 6:** linear point editing — double-tap/`beginLinearEdit` a
    line/arrow, drag vertices, insert points by dragging midpoints, exit on
    tool change / click-away; suppresses box-transform handles. 6 tests ported
    from LinearEditTests. Still to port: elbow arrows, image-crop drag,
    flowchart spawning.
  - **T4 slice 7:** interactive image cropping (`CropGeometry` in `@xs/geometry`
    + crop mode in the editor) — `beginCropEdit`, eight crop handles, drag to
    reframe with the crop rectangle tracking the pixels (clamped to the full
    image), exit on tool change / tap-away. 9 tests ported from ImageCropTests.
    Still to port: elbow arrows, flowchart spawning.
  - **T4 slice 8:** elbow-arrow router (`ElbowArrow` in `@xs/geometry`) — A\*
    over a non-uniform grid with dynamic AABBs and a bend-count heuristic →
    axis-aligned routes between free points or bound boxes; plus segment
    editing (fixable segments, drag-to-move with bend insertion,
    follow-endpoints). 12 tests ported from ElbowArrowTests. Still to port: the
    elbow editor wiring + flowchart spawning.
  - **T4 slice 9 (completes T4):** elbow editor wiring (`setElbowed`,
    `routeElbowArrow` on create + bound-arrow updates, segment-drag via the
    linear-edit overlay with fixed-segment pinning, `resetElbowShape`) and
    flowchart spawning (`addFlowchartNode` — clone the source node offset in a
    direction with stagger, link by a bound elbow arrow). 15 tests ported from
    ElbowArrowEditorTests + FlowchartTests. **`@xs/editor` is now feature-complete.**
- **T5 — Svelte UI (in progress):** `@xs/svelte` exposes a reactive `EditorStore`
  bridge (the runes-ready wrapper over `@xs/editor` + `@xs/render`, mirroring the
  Swift `EditorModel`): view→scene pointer forwarding, viewport pan/zoom, tool +
  style commands, generators, undo/redo, theme, Canvas2D render, SVG export and
  `.excalidraw` document round-trip — 11 tests. `apps/web` is a runnable Vite +
  Svelte 5 example (toolbar, canvas with pointer + wheel pan/zoom, properties,
  actions, generators, zoom, theme, export) — builds clean, `svelte-check` 0
  errors, exercised in CI.
  - **T5 slice 2:** the **interactive overlay** (`renderOverlay` in `@xs/render`,
    parity InteractiveRenderer) — selection box, transform handles, rotation
    handle, dashed marquee, snap guides, linear/elbow/crop edit handles; wired
    through `EditorStore.renderOverlay` and drawn by the canvas. Plus on-canvas
    **text editing** (a floating editor placed by the text tool) and
    **keyboard shortcuts** (tool keys, ⌘Z/⌘⇧Z, ⌘D, ⌘A, Delete). 6 more tests.
    Still to do: laser/eraser trails, command palette, image import, two-finger
    gestures.
  - **T5 slice 3:** laser/eraser fading **trails** (`TrailStore` in `@xs/svelte`,
    parity TrailStore) — laser paints a trail and creates nothing, the eraser
    paints a trail and still erases; rendered in the overlay with age-based
    opacity and animated by the canvas. Plus **image import** (file → data-URL →
    downscaled image element) and toolbar **align / flip / z-order** actions.
    5 more tests (TrailStore + laser/eraser via the store).
  - **T6 — Parity hardening (started):** a **Playwright** E2E suite that drives
    the real built app in Chromium (mirroring the iOS `SmokeUITests`) and
    asserts against the live `EditorStore` exposed on `window`: draws every
    shape tool, box-selects + duplicates + undo/redo, inserts all generators,
    types on-canvas text, paints a laser trail, zooms, toggles theme, and
    exports an SVG — capturing a screenshot at each step. It already caught a
    real bug: in Svelte 5 runes mode the app's UI/canvas didn't repaint on
    store changes (plain reads aren't tracked) — fixed with a `rev`-keyed
    `$derived` view. Runs in CI (`web` workflow `e2e` job).
  - **T6 slice 2:** **golden snapshots** (`@xs/render` `golden.test.ts`) — a
    representative corpus (the shared `../Fixtures/minimal_scene.excalidraw`
    plus a synthetic `rich_scene` covering every renderable element kind at
    fixed seeds) locked against committed goldens: the **canonical-JSON**
    golden is language-neutral (the Swift twin's sorted-key `JSONEncoder`
    emits the same bytes, so it doubles as the cross-language serialization
    contract) and the **SVG** golden pins the full TS render pipeline
    (rough.js + perfect-freehand + serialization). A determinism check proves
    repeated renders are byte-identical. Regenerate with `UPDATE_GOLDEN=1`.
  - **T6 slice 3:** two rendering/UX bugs the E2E pass surfaced, now fixed with
    regression tests: (1) **arrows drew no arrowhead** — the canvas renderer
    never ported `SceneRenderer.drawArrowheads`, so arrows were bare lines;
    (2) **sticky notes couldn't hold text** — inserting a note never opened its
    bound-text editor, there was no double-click-to-edit, and the renderer
    didn't centre container-bound text. Covered by `scene-renderer.test.ts`
    (arrowhead stroke/fill + bound-text centring) and `editor-store.test.ts`
    (insert-note-edits-text + double-click re-edit), plus the Playwright suite
    now asserts the arrow's `endArrowhead` and types a sticky-note label.
  - **T6 slice 4:** **rough.js op-set parity** (`@xs/render` `rough-parity.test.ts`)
    — the TS mirror of Swift's `RoughJSParityTests`. The Swift `RoughKit` is a
    re-port of rough.js pinned to reference op-sets captured from the real
    rough.js 4.6.6 at a fixed seed; the TS twin renders with that *same*
    `roughjs@4.6.6`, so asserting against the *same* constants proves all three
    agree (rough.js ⇔ Swift `RoughKit` ⇔ TS `@xs/render`) for line, rectangle,
    ellipse and the filled-rectangle outline (fresh seed, independent of fill),
    with hachure fill bounded to the same op-count magnitude. Render geometry
    can't silently drift between the two implementations.
  - **T6 slice 5:** three interaction bugs/gaps the feature pass surfaced, fixed
    with unit + E2E regression coverage: (1) **moving a sticky note stranded its
    bound text** — the move snapshot didn't expand to group siblings / bound
    text, so the label stayed behind and the group's bounds ballooned; the move
    now carries group + bound text; (2) **double-clicking a line/arrow now enters
    point ("spline") editing** (`doubleClickAt` → `beginLinearEdit`) so vertices
    drag and midpoints split; (3) a **fill-pattern selector** (hachure /
    cross-hatch / solid / zigzag) wired to `setFillStyle`. E2E asserts the moved
    note keeps a tight selection, a line vertex drags, and the pattern change
    lands on the element.
