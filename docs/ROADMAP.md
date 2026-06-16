# Excalidraw-Swift — Roadmap

Vertical-slice-first delivery: get a thin end-to-end path working early (draw → rough render → select/move → save/load → export), then widen feature by feature. Each phase ends with a working, tested build. Coverage gate (≥90%) and CI green are exit criteria for every phase.

Legend: 🎯 milestone deliverable · 🧪 test focus · ⚠️ risk/hard part.

---

## Phase 0 — Foundations & CI
**Goal:** buildable workspace, test harness, coverage gating.
- SwiftPM workspace with the package split from [PLAN.md §2](./PLAN.md): `ExcalidrawMath`, `ExcalidrawModel`, `ExcalidrawGeometry`, `RoughKit`, `FreehandKit`, `ExcalidrawRender`, `ExcalidrawUI`, `ExcalidrawApp`.
- Xcode app target (iOS 17+), iPhone + iPad. SwiftLint + formatting.
- GitHub Actions: build + `swift test` + `xcodebuild test`, coverage report, 90% gate, golden-image diff artifacts.
- Import upstream test fixtures and a corpus of `.excalidraw` sample files.
- 🎯 CI green on an empty but wired project; one trivial test per package.

## Phase 1 — Domain core: model + geometry + file format ✅
**Goal:** the engine, fully testable, no UI.

> **Status: complete.** Delivered: `ExcalidrawModel` (element model, file format, Scene, Store/Delta/History, Restore), `ExcalidrawMath` (point/vector/angle/range/line/segment/triangle/rectangle/polygon/ellipse/curve), `ExcalidrawGeometry` (bounds + hit-testing). `.excalidraw` round-trips diff-clean against the fixture corpus. **Deferred to later increments/phases:** full rocicorp fractional-indexing + legacy binding-v1 migration (incremental), property-level partial deltas & AppState history (collab-oriented), exact cubic-Bézier bounds and rounded-corner hit-testing, and the heavy curve algorithms — Newton curve↔line intersection, Legendre–Gauss arc length, elbow A* (Phase 7).
- `ExcalidrawMath`: port `packages/math` (point, vector, line, segment, curve, ellipse, polygon, angle, range) 1:1. 🧪 property/fixture tests.
- `ExcalidrawModel`: `ExcalidrawElement` enum + base props, AppState, Scene store with indices, fractional index, Store/Delta/History. Custom `Codable`.
- Persistence: port `restore.ts` as the single load path (index gen, ref repair, binding migration, normalization, clamping). PNG-scene embed deferred.
- `ExcalidrawGeometry`: bounds (incl. rotated + Bézier bbox), hit-testing (ray cast + distance), basic curve sampling. *(Newton intersect, elbow A*, Legendre-Gauss deferred to Phase 7.)*
- 🧪 Codable round-trip on the sample corpus (incl. older schema versions); structural equality after restore→encode; hit-test fixtures.
- ⚠️ Round-trip fidelity vs excalidraw.com — build the interop corpus now.
- 🎯 Load any real `.excalidraw`, mutate via API, save it back, diff-clean.

## Phase 2 — RoughKit + first pixels ✅
**Goal:** the hand-drawn look, one shape on screen.

> **Status: complete.** `RoughKit` ports rough.js — RNG matched to `Math.imul(48271, seed)`, the double-stroke `_line`/`_doubleLine`/`linearPath`, `polygon`/`rectangle`, `curve`/`_computeEllipsePoints` ellipses, and fills (solid/hachure/cross-hatch/zigzag). `ExcalidrawRender` adds `RoughOptionsBuilder` (`generateRoughOptions`), `ElementDrawable`, `ShapeCache`, and a `SceneRenderer` (viewport transform, grid, per-element transform/opacity, stroke/fill, Core Text, images, freedraw). `SceneCanvasView` renders a real scene via SwiftUI `Canvas` + `withCGContext`; the app loads and draws a bundled `.excalidraw` (verified on the iOS 17 simulator). **rough.js parity validated:** RoughKit's RNG, line, rectangle, ellipse, and outline-with-fill match rough.js 4.6.6 exactly to 1e-4 (reference captured via `scripts/rough_ref.cjs`, asserted in `RoughJSParityTests`). **Deferred:** hachure fill is visually faithful but not line-identical (scan-line edge handling differs); perfect-freehand pressure outlines and bundled Excalidraw fonts + exact text metrics (Phase 4); committed golden-image references; Metal fast-path if profiling needs it.
- `RoughKit`: seeded RNG, polyline perturbation, `Drawable` generation for rectangle/ellipse/polygon/linearPath/curve; fill styles (hachure, cross-hatch, solid, zigzag); dash/dotted; roughness scaling; `preserveVertices`. Renders into `GraphicsContext`/`CGContext`.
- `ExcalidrawRender`: SceneRenderer (static), ShapeCache, `Viewport` transforms, grid.
- Minimal `CanvasView` rendering a loaded scene (read-only) with pan/zoom.
- 🧪 RoughKit determinism (seed → identical paths); golden-image tests vs JS-rendered references for rect/ellipse/diamond/line across fill+stroke styles.
- ⚠️ rough.js visual fidelity — this phase de-risks the whole project.
- 🎯 Open a real `.excalidraw` and see it rendered with the correct hand-drawn look.

## Phase 3 — Interaction loop & first tools (the vertical slice closes) ✅
**Goal:** draw, select, move, resize, rotate, undo, export — end to end.

> **Status: complete.** New pure `ExcalidrawEditor` module: `PointerEvent`, `Tool`, `CurrentItemProperties`, `Transform` (resize/scale/translate/rotate math + handle layout), and the `EditorController` state machine (create-by-drag, select, multi-select box, move, resize via 8 handles, rotation, undo/redo, delete). `ExcalidrawRender` adds `InteractiveRenderer` (selection box + handles + marquee) and `Exporter` (PNG fit-to-content). `ExcalidrawUI` adds `EditorModel` (SwiftUI bridge), `EditorView` (toolbar + canvas + properties bar), and `PointerInputView` (raw `UITouch`: pressure, pencil-vs-finger, palm rejection, two-finger pan/zoom). The app is the editor; the XCUITest draws → exports → undoes on the iOS 17 simulator. **Deferred:** arrow/freedraw/text/image tools and rich properties (Phase 4); rotated-element resize is AABB-approximate; Apple Pencil hover and coalesced-touch freehand (Phase 4/5).
- Custom `UIViewRepresentable` exposing raw `UITouch` (force, type, coalesced, hover). `PointerController` state machine + `GestureCoordinator` (1-finger action, 2-finger pinch-zoom/pan).
- Tools: selection, rectangle, diamond, ellipse, line. Drag-to-create; multi-select; transform handles (pointer-type-aware sizes); rotation; move.
- Interactive overlay Canvas (selection box, handles, snap-to-grid).
- Undo/redo wired to Store/History.
- Exporter: PNG via `UIGraphicsImageRenderer`.
- Minimal toolbar + a few properties (stroke color, width).
- 🧪 Transform math tests; XCUITest: draw rect → move → resize → undo → export, on iPhone + iPad.
- 🎯 **Vertical slice complete**: create/edit a drawing from scratch and export it.

## Phase 4 — Full tool set & properties ✅

> **Status: complete.** Tools added: arrow (with arrowheads), freedraw (FreehandKit pressure outlines), text (on-canvas editing), image insert (PhotosPicker), eraser, hand. Properties: stroke/background colour, fill style, stroke style, stroke width, opacity — applied to current-item defaults and the selection. Actions: group/ungroup, duplicate, lock, z-order (front/back/forward/backward), align, flip — all undoable. Copy/paste via the `.excalidraw` payload (carries image files). SVG export (`SVGExporter`). New `FreehandKit` (perfect-freehand port). Full toolbar + properties bar in `EditorView`; XCUITest draws a shape, freedraws, places text, and exports on the iOS 17 simulator. **Deferred:** font family/size & arrowhead-type pickers, exact perfect-freehand parity (no local reference), bundled fonts + exact text metrics, laser pointer, eraser/laser animated trails (Phase 5+).

## Phase 4 — Full tool set & properties (original plan)
**Goal:** all core element types and styling.
- Tools: arrow (straight/curved), freedraw (`FreehandKit` port, pressure via `UITouch.force` + coalesced touches), text (Core Text `TextLayout`, on-canvas editing), image (insert from Photos/Files, files store), eraser (AnimatedTrail + intersection), hand/pan, laser.
- Properties panel: background color, fill style, stroke style, roundness, opacity, font family/size/text align, arrowheads, arrow type. Color picker + eyedropper.
- Actions: group/ungroup, duplicate, delete, align/distribute/flip, z-order, lock.
- Copy/paste via `UIPasteboard` (native + Excalidraw formats).
- SVG export.
- 🧪 FreehandKit outline tests; TextLayout metrics vs JS fixtures; per-tool e2e steps.
- ⚠️ Core Text metric parity — validate early in this phase.
- 🎯 Feature-complete single-user editor for all core element types.

## Phase 5 — Adaptive UI for iPhone & iPad ✅
**Goal:** great UX on both form factors, Pencil-first.

> **Status: complete.** Testable cores: `DeviceClass`/`FormFactor` breakpoints, `Shortcuts` (key chords → commands), `CommandRegistry` (palette + fuzzy search), `Theme`/`ThemeFilter` (dark mode via invert + 180° hue-rotate), `SceneDocument` (encode/decode through restore). `EditorModel` adds zoom (in/out/reset/fit), command dispatch, clipboard (`Pasteboard`), theme/zen toggles, and document save/load. `EditorView` is size-class adaptive (toolbar top on iPad / bottom on iPhone), with a zoom/theme/zen/palette footer, on-canvas context menu, hardware-keyboard shortcuts, and a searchable command palette. The XCUITest passes on both iPhone (compact) and iPad (regular) simulators. **Deferred:** Files-app `DocumentGroup` browser + autosave wiring (persistence core is done and tested), Apple Pencil hover (17.5+) and Pencil Pro, full font/arrowhead pickers.
- Size-class-adaptive layout: iPhone bottom toolbar + bottom-sheet properties, fullscreen dialogs; iPad side panels, floating/docked, hover affordances.
- Apple Pencil: hover preview (17.5+), palm rejection, pen-mode toggle; (Pencil Pro squeeze/roll behind availability checks).
- Context menu (long-press / right-click), command palette, keyboard shortcuts (iPad hardware keyboard), zoom controls, dark mode, zen/view modes.
- Document browser integration (Files app), autosave, recent docs.
- 🧪 Snapshot tests across size classes/orientations; XCUITest on iPhone + iPad; Pencil/pressure paths via injectable input.
- 🎯 Ships as a usable iPhone + iPad app.

## Phase 6 — Library, persistence polish, snapping & binding ✅
**Goal:** the "important" tier from the investigation.

> **Status: complete.** `ExcalidrawLibrary` (read v1/v2, write v2) + a library panel (add selection, thumbnail grid, stamp) with disk persistence (`LibraryStore`) and `.excalidrawlib` import/export. Font controls (family + size) for text. Object + grid + gap (distribution) `Snapping` with live guide lines and a toggle. Arrow↔shape `Binding` (bind on draw, follow on move/resize). `Frames` (frame tool, centre-containment membership, move-with-children, border/name render + child clipping). Linear element point editing (double-tap → drag/insert vertices). Interactive image crop (double-tap → drag the eight handles; `CropGeometry` + crop-aware rendering). Element hyperlinks (context-menu "Link…"). Stats readout in the footer. **Deferred:** PNG scene-embed round-trip.
- Library (`.excalidrawlib`): save/browse/search/drag-to-canvas; local persistence.
- Object snapping (point + gap snaps) and snap-line rendering; midpoint snapping.
- Arrow↔shape binding (suggested binding, focus point, fixed-point modes); linear element midpoint editing.
- Image crop editor. PNG scene-embed round-trip. Stats panel. Element linking. Frames (containers, clipping, names).
- 🧪 Binding + snapping fixtures; library round-trip; frame clipping golden images.
- 🎯 Parity with everyday excalidraw.com usage.

## Phase 7 — Advanced geometry & remaining parity ✅
**Goal:** the hard algorithms and long-tail features.

> **Status: complete.** Cubic-Bézier math (`Curve`): Legendre–Gauss N=24 arc length (full + partial), length-parameterized point lookup, curve↔line-segment Newton intersection, and closest-point search (ports `packages/math/src/curve.ts`). Elbow arrows: `Heading` + `ElbowArrow.route` — dynamic touching AABBs, a non-uniform grid, and A* with turn penalty, reverse-prevention, obstacle blocking, and a segment-count heuristic, simplified to corner points (ports `heading.ts` + `elbowArrow.ts`); wired into creation, binding re-route, and a toolbar toggle. Fixed-segment elbow editing: drag any segment to pin it (`ElbowArrow.segments`/`moveSegment`; dragging a first/last segment inserts a bend), recorded as a `FixedSegment`; pinned segments survive endpoint re-routes via `followEndpoints`, and "Reset Arrow Shape" releases all pins and re-routes. Localization is wired through the UI: `EditorModel.locale`/`t(_:)` localize the context menu and `layoutDirection` mirrors the canvas for RTL (English/Spanish/Arabic). Performance: viewport `Culling` skips off-screen elements; `DirtyRegion` computes the changed-bounds and `SceneRenderer.render(clip:)` supports incremental repaint (the live SwiftUI `Canvas` is immediate-mode, so it uses full-redraw + culling; the clip path is ready for a future retained-layer/Metal renderer). Embeddable/iframe placeholder rendering. Flowchart helpers: `addFlowchartNode` spawns a same-style node linked by a bound elbow arrow (Tab / ⌥+arrow), staggering repeats. Freehand shape recognition (Apple "Snap to Shape"): `ShapeRecognizer` (RDP + collinear cleanup, corner/circularity classification, and radial/feature detectors) snaps a held stroke to a rectangle/ellipse/diamond/triangle/line plus pentagon, hexagon, star, heart, cloud, and speech bubble — the latter regenerated cleanly via `ShapeGenerator` and emitted as closed polygon-lines; triggered by a hold-to-snap dwell while drawing. Fill controls: a fill-colour swatch row plus a fill-style picker (hachure/cross-hatch/solid/zigzag) that appears once a fill is set; closed shapes — including polygon-flagged lines and recognized triangles — fill from the background colour. Sticky notes: the post-it tool drops a filled, rounded note with a centered container-bound text label (grouped, colour from the fill swatch), edited on creation or double-tap; the renderer centres bound text in its container. Text resizing scales the font size with the box (rendered crisply via Core Text antialiasing, no bitmap scaling). Sloppiness (architect/artist/cartoonist roughness) and an edges sharp/round control in the properties bar; new elements default to rounded edges, so multi-point lines/arrows render as Catmull-Rom splines and rectangles draw rounded corners. **Deferred:** full `WKWebView` embedding (UI/security), Metal fast-path.
- Elbow arrows: port `heading.ts` + `elbowArrow.ts` (A* grid routing, fixed segments). Newton curve↔line intersection; Legendre-Gauss arc length. (Enables precise binding/curve interactions.)
- Embeddables/iframes (where iOS allows), flowchart helpers.
- Localization infra + initial locales (RTL support).
- Performance pass: profiling, dirty-region overlay, optional Metal fast-path if needed.
- 🎯 Feature parity (single-user) with upstream.

## Phase 7.5 — Rendering acceleration & performance
**Goal:** scale to large scenes and crisp high-zoom without losing the hand-drawn look — measure first, accelerate in stages, and reach for Metal only if the data demands it.

> **Readiness.** The architecture is ready to accept a new renderer backend: `SceneRenderer` is isolated in `ExcalidrawRender`, the model/editor are renderer-agnostic, and `DirtyRegion` + `SceneRenderer.render(clip:)` already exist as groundwork (built in Phase 7, not yet wired into the live canvas). What's missing *before* Metal is profiling data — today's real cost is "repaint the whole scene every frame," not necessarily CoreGraphics rasterization — and a pixel baseline to catch regressions. So this phase front-loads both and treats Metal as the last, gated stage. Each stage is independently shippable; **stop at the first stage that meets the target.**

### Stage A — Measure + safety net (prerequisite) ✅
> **Status: done.** `RenderBenchmarkTests` times steady-state `SceneRenderer.render` on synthetic grids (prints `BENCH` lines; asserts correctness, not wall-clock, so CI doesn't flake). `GoldenImageTests` diffs three deterministic shapes-only scenes against committed PNG references in `Golden/` (tolerant pixel compare; references excluded from the SwiftPM target and read via `#filePath`). **First numbers (debug build, CPU):** full-scene repaint ≈25 ms (100 elems) → 44 ms (1500 elems); the same 1500-element scene zoomed-in with culling ≈17 ms. Takeaway: cost is dominated by repainting the whole scene every frame — exactly what Stage B targets. (Device-side ms overlay still TODO.)
- **Benchmark harness:** synthetic heavy scenes; headless timing of `SceneRenderer.render`; an on-device ms/FPS overlay (TODO).
- **Golden-image references** (the long-deferred item): committed pixel baselines, diffable within tolerance.
- 🎯 Exit: numbers identifying the real bottleneck + a baseline to diff against. 🧪 perf benchmarks + golden images.

### Stage B — Layered static/dynamic split (biggest ROI, no Metal) ✅
> **Status: done.** `SceneRenderer.render` gained `skipping:`/`fillBackground:`; `StaticLayerCache` memoizes the committed scene as an offscreen image. During an interaction `EditorModel` captures the **dynamic set** (the moved/created element plus its bound arrows/text and any frame children — so anything that actually changes mid-drag is excluded from the cache), builds the static layer once, and each frame blits it (via SwiftUI `Image`, orientation-safe) + redraws only the dynamic elements and the overlay; idle frames render in full. **Measured:** a 1500-element frame drops from ~45 ms (full repaint) to ~11 ms (layered) — **4.1× faster** — and `testLayeredCompositeMatchesFullRender` proves the composite equals a full render. Builds for iOS.
- Split the canvas into a cached **static layer** and a **dynamic overlay**; repaint only the overlay each frame.
- 🎯 Exit: smooth drag/draw/select on large scenes with the CPU renderer. *(Device-side timing pending a signing/test-plan setup — see note.)*

### Stage C — Retained tile cache + crisp zoom
- Cache rasterized content (tiles / `CALayer`) and **recomposite** on pan/zoom instead of repainting; re-rasterize vectors at the new zoom so high zoom stays sharp (fixes the current `Canvas` magnification softness).
- 🎯 Exit: pan/zoom is composite-only; zoom is crisp at every level.

### Stage D — Metal backend (gated)
- Introduce a `Renderer` protocol so the CoreGraphics `SceneRenderer` and a new `MetalSceneRenderer` are interchangeable; editor/model unchanged. CG stays the default/fallback; Metal behind a flag until proven.
- Tessellate rough.js output: fills → triangulated polygons, strokes → expanded quads; text via a CoreText glyph atlas. GPU compositing of cached tiles + transforms → near-free pan/zoom/rotate, 120 Hz ProMotion / low-latency Pencil.
- ⚠️ Largest single chunk and a new bug class (tessellation/AA/text correctness).
- **Decision gate:** only build Stage D if Stage A shows CG *rasterization* (not redraw-everything, which B/C fix) is the bottleneck on realistic scenes, **or** crisp high-zoom / guaranteed 120 Hz is a hard product requirement.
- 🎯 Exit: GPU renderer at parity with the golden images, measurably faster on the heavy benchmark, behind a CG fallback.

**Sequencing:** A → B → *(measure)* → C → *(measure)* → D. The honest expectation is that A + B (and maybe C) deliver the perceived speedup; D is for proven raster-bound workloads or a 120 Hz/zoom-crispness mandate.

## Phase 8 — Collaboration & cloud (optional / future)
**Goal:** multiplayer, if pursued.
- Reuse Delta/Store sync unit + fractional indexing already in place.
- WebSocket/Firebase transport, collaborator cursors/presence, conflict resolution, follow mode.
- Mermaid-to-diagram and AI/magic features as separate opt-in modules.
- 🎯 Real-time collaboration parity.

> **Generators shipped (additive, no architecture change):** group-aware selection; **tables** (a grid of container-bound text cells, add row/column, edit via double-tap); **charts** (bar/line from a number series, via a values-input sheet) — both emit standard grouped elements and round-trip through `.excalidraw`. **Remaining from this group:** Mermaid → diagram (a text→elements parser; Swift flowchart-subset or JSC-embedded mermaid.js).

---

## Known gaps & deferred items

The single source of truth for what's **not** yet implemented, kept in sync with the code. Phases 0–7 + tables/charts are complete (474 tests, ~94% logic coverage, CI green); everything below is deliberately deferred, not forgotten.

**Major features**
- **Collaboration & cloud** (Phase 8) — real-time multiplayer, presence, cursors, follow mode. Not started; the data model (deltas, fractional indices, version nonces) is built collab-ready.
- **Mermaid → diagram** — no text→diagram parser yet. Output mapping is trivial (reuses nodes + bound elbow arrows); the work is the parser (Swift flowchart-subset, or JSC-embedded `mermaid.js` for full coverage).
- **Embeddables / iframes** — render as labelled placeholders only; no live `WKWebView` embedding, URL allow-list, or interaction (UI/security work).

**Rendering & performance** — planned as **Phase 7.5** (above)
- **Retained-layer / Metal renderer** — the live SwiftUI `Canvas` is immediate-mode CoreGraphics (full-redraw + viewport `Culling` + `ShapeCache`). No static/dynamic layer split or GPU path, so high-zoom content can soften. `DirtyRegion` + `SceneRenderer.render(clip:)` are built and tested as the groundwork; not wired into the live canvas.
- **Golden-image render tests** — RoughKit numeric parity is asserted, but committed pixel-reference images are not (Stage A of Phase 7.5).

**Fidelity**
- **Fonts** — bundled Excalidraw fonts (Excalifont/Virgil/etc.) + exact Core Text metrics; currently maps to system fallbacks (Bradley Hand / Helvetica / Menlo).
- **Hand-drawn parity** — hachure fill and perfect-freehand outlines are visually faithful but not line-identical to upstream (scan-line/edge handling differs).

**UI polish**
- **Custom color picker** + eyedropper — only the 5 preset stroke/fill swatches today.
- **Arrowhead-type picker** — the model stores start/end arrowheads; no UI to change them.
- **Files-app `DocumentGroup` browser + autosave + recents** — the persistence core (`SceneDocument`) is done and tested; not wired to a document browser.
- **Laser pointer** and animated eraser trail.

**Apple Pencil**
- **Hover preview** (17.5+) and **Pencil Pro** squeeze/roll. Pressure, tilt, palm rejection, and the hold-to-snap dwell are implemented.

**Persistence**
- **PNG scene-embed round-trip** — exporting a PNG with embedded scene metadata so it can be re-opened as an editable drawing.

**Collab-oriented model internals** (built lean until Phase 8)
- Full rocicorp fractional-indexing edge cases + legacy binding-v1 migration; property-level partial deltas & AppState history.

---

## Sequencing rationale
- **Phases 0–3 close the vertical slice** and de-risk the two scariest unknowns early: rough.js fidelity (Phase 2) and the raw-touch interaction layer (Phase 3).
- **File-format fidelity is front-loaded** (Phase 1) so every later phase reads/writes real Excalidraw files.
- **Hard algorithms (elbow A*, Newton intersect) are deferred** (Phase 7) behind the features that don't need them, so they never block a shippable build.
- **Collaboration is last and optional** but the data model (deltas, fractional indices, version nonces) is built collaboration-ready from Phase 1.
