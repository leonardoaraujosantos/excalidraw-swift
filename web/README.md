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
│   ├── geometry/  @xs/geometry — bounds, hit-test, snapping, frames     🟡 T2
│   ├── render/    @xs/render — Canvas2D renderer, rough.js, SVG/PNG     🟡 T3
│   ├── editor/    @xs/editor — tools, selection/transform, actions      🟡 T4
│   ├── svelte/    @xs/svelte — Svelte 5 runes store + components          (T5)
│   └── protocol/  @xs/protocol — collaboration wire schema               (T7)
├── apps/web/      browser app                                             (T5)
└── server/        WebSocket relay                                         (T7)
```

## Develop

Requires Node ≥ 20.19 and pnpm 10.

```sh
pnpm install
pnpm test          # vitest across all packages
pnpm typecheck     # tsc --noEmit per package
pnpm lint          # biome
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
