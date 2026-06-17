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
│   ├── editor/    @xs/editor — tools, selection, generators, smart        (T4)
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
