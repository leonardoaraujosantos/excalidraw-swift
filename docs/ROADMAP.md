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

## Phase 7.5 — Rendering acceleration & performance ✅
**Goal:** scale to large scenes and crisp high-zoom without losing the hand-drawn look — measure first, accelerate in stages, and reach for Metal only if the data demands it.

> **Status: complete.** Stages A–D shipped plus follow-up tiers; the Metal GPU backend is runtime-selectable behind the CG fallback and 1.9–2.9× faster than CPU on device across all component types (details per stage below).

> **Readiness.** The architecture is ready to accept a new renderer backend: `SceneRenderer` is isolated in `ExcalidrawRender`, the model/editor are renderer-agnostic, and `DirtyRegion` + `SceneRenderer.render(clip:)` already exist as groundwork (built in Phase 7, not yet wired into the live canvas). What's missing *before* Metal is profiling data — today's real cost is "repaint the whole scene every frame," not necessarily CoreGraphics rasterization — and a pixel baseline to catch regressions. So this phase front-loads both and treats Metal as the last, gated stage. Each stage is independently shippable; **stop at the first stage that meets the target.**

### Stage A — Measure + safety net (prerequisite) ✅
> **Status: done.** `RenderBenchmarkTests` times steady-state `SceneRenderer.render` on synthetic grids (prints `BENCH` lines; asserts correctness, not wall-clock, so CI doesn't flake). `GoldenImageTests` diffs three deterministic shapes-only scenes against committed PNG references in `Golden/` (tolerant pixel compare; references excluded from the SwiftPM target and read via `#filePath`). **First numbers (debug build, CPU):** full-scene repaint ≈25 ms (100 elems) → 44 ms (1500 elems); the same 1500-element scene zoomed-in with culling ≈17 ms. Takeaway: cost is dominated by repainting the whole scene every frame — exactly what Stage B targets. (Device-side ms overlay still TODO.)
- **Benchmark harness:** synthetic heavy scenes; headless timing of `SceneRenderer.render`; an on-device ms/FPS overlay (TODO).
- **Golden-image references** (the long-deferred item): committed pixel baselines, diffable within tolerance.
- 🎯 Exit: numbers identifying the real bottleneck + a baseline to diff against. 🧪 perf benchmarks + golden images.

### Stage B — Layered static/dynamic split (biggest ROI, no Metal) ✅
> **Status: done.** `SceneRenderer.render` gained `skipping:`/`fillBackground:`; `StaticLayerCache` memoizes the committed scene as an offscreen image. During an interaction `EditorModel` captures the **dynamic set** (the moved/created element plus its bound arrows/text and any frame children — so anything that actually changes mid-drag is excluded from the cache), builds the static layer once, and each frame blits it (via SwiftUI `Image`, orientation-safe) + redraws only the dynamic elements and the overlay; idle frames render in full. **Measured (Mac):** a 1500-element frame drops from ~45 ms (full repaint) to ~11 ms (layered) — **4.1×** — and `testLayeredCompositeMatchesFullRender` proves the composite equals a full render. **Measured on device (iPad 9):** n=500 30.8→2.9 ms (**10.6×**), n=1500 36.6→8.1 ms (**4.5×**), via the app-hosted `ExcalidrawAppBenchmarks` target (`-only-testing:ExcalidrawAppBenchmarks`).
- Split the canvas into a cached **static layer** and a **dynamic overlay**; repaint only the overlay each frame.
- 🎯 Exit: smooth drag/draw/select on large scenes with the CPU renderer — confirmed on real hardware.

### Stage C — Gesture snapshot + crisp zoom ✅
> **Status: done.** On a two-finger pan/zoom, `EditorModel` snapshots the scene once at the gesture's start viewport (`beginViewportGesture`) and each frame composites that snapshot transformed by the live pan/scale (`gestureSnapshot` → a scale + offset rect, drawn via SwiftUI `Image`); on lift it re-renders the whole scene crisply at the settled viewport (`endViewportGesture`). So a pan/zoom frame is one image blit regardless of scene size, and zoom is sharp at rest (mid-pinch the bitmap scales, then snaps crisp — standard). Validated on the iPad (UI test passes with the gesture path wired). *(A persistent tile cache across gestures is a future refinement; the per-gesture snapshot already makes pan/zoom O(1).)*
- 🎯 Exit: pan/zoom is composite-only during the gesture; full crisp re-render on settle.

### Stage D — Metal backend ✅
> **Status: complete.** A `SceneRendering` protocol makes the CoreGraphics `SceneRenderer` and a new `MetalSceneRenderer` (module `ExcalidrawMetal`) interchangeable; the editor/model are renderer-agnostic. CG stays the default and the automatic fallback — `EditorModel.setRenderer(_:)`/`toggleRenderer()` switch backends at runtime, and selecting Metal on a device without a GPU silently falls back to CG (the footer toggle only appears when `isMetalAvailable`). The GPU path tessellates rough.js output (`Tessellator`: Bézier flattening, ear-clipped fills, round-joined/round-capped stroke triangles, filled/line arrowheads) into per-vertex-colored triangles (`SceneGeometry`), rasterizes them with runtime-compiled Metal shaders and 4× MSAA into an off-screen texture, reads back a `CGImage`, and composites it between a CG background/grid pass and a CG overlay pass (text, images, frames, freedraw, embeddables, dashed strokes and frame-clipped children stay on CG — `handledIDs` is the exact overlay skip set). 4× MSAA keeps shapes crisp under high zoom. Validated: `Tessellator`/`SceneGeometry` pure-math unit tests, a GPU off-screen-readback parity test vs CG (skips on hosts with no device), renderer-toggle/fallback tests, and an on-device iPad UI smoke test (draw → move → zoom → export → toggle back) under the Metal backend. Coverage ≥90%, swiftlint `--strict` clean.
- ⚠️ Known scope limits (CG handles these correctly, so output stays faithful): z-order between a GPU shape and a *later* text/image is shape-under-overlay (text/images always composite on top); dashed/dotted strokes, freedraw, and frame-clipped children render via CG; the GPU pass ignores the incremental-redraw `clip` (it repaints the full viewport — idempotent, perf-only).
- 🎯 Exit met: GPU renderer at parity with the golden images, behind a CG fallback, runtime-switchable, verified on device.

> **On-device benchmark (`ExcalidrawAppBenchmarks/RendererComparisonBenchmark`, iPad).** A head-to-head CPU-vs-GPU stress test with a per-phase breakdown. Building it surfaced and fixed three real issues in the GPU path: (1) a per-emit `reserveCapacity` that defeated `Array`'s geometric growth and made geometry build **O(n²)** (~8 s for 200 shapes); (2) excessive triangle count — a round disc at *every* stroke vertex — cut ~5.5× by angle-thresholded joins + endpoint-only caps + lighter Bézier flattening; (3) full re-tessellation every frame, fixed with a per-element `GeometryCache` (cold→warm rebuild 2230 ms→36 ms for 1500 shapes). Net effect on device: Metal went from ~35 s/frame to ~33–57 ms/frame, *competitive* with CoreGraphics but not yet ahead for full-repaint frames. Regression tests guard the O(n²) build and the cache behavior.

> **Performance tiers (follow-up PR).** A round of protocol-preserving optimizations then made Metal clearly faster than CoreGraphics: **viewport culling** in the geometry build (parity with `SceneRenderer`), **persistent GPU resources** (reuse MSAA/resolve textures, a growable vertex buffer, and the readback buffer instead of per-frame allocation), **packed vertex color** (RGBA8 in one float — 3 floats/vertex, half the bandwidth), **freedraw on the GPU** (tessellate the perfect-freehand outline, removing the biggest CG overlay cost), and a **GPU background clear** (drop the CG background pass in the gridless case). Steady-state on device, 1200×800: shapes-only n=500 `cpu=14.0 metal=6.5 (2.1×)`, n=1500 `cpu=15.0 metal=8.8 (1.7×)`; mixed n=500 `cpu=30.7 metal=10.7 (2.9×)`, n=1500 `cpu=36.7 metal=20.6 (1.8×)` — **Metal 1.7–2.9× faster**, with `gpu` down to ~3 ms and `bg` to 0. Deferred (own follow-up): direct-to-`CAMetalLayer` (no readback), GPU text glyph atlas, GPU images, GPU dashed strokes; zoom-adaptive flattening was skipped to preserve the zoom-independent geometry cache.

> **Direct-to-drawable (follow-up PR).** The `SceneRendering` path renders to an off-screen texture, reads it back as a `CGImage`, and composites into a `CGContext`. The direct path skips that round-trip: `MetalRenderContext.renderToDrawable` presents straight into a `CAMetalLayer` drawable (second `bgra8Unorm` pipeline, since drawables don't support `rgba8Unorm`), and `renderNoReadback`/`renderDirectFrame` measure the GPU frame without read-back. A `MetalCanvasView` (iOS, `CADisplayLink`-driven) wires this into the live benchmark as a "Direct" backend. On device, 1200×800, the read-back vs direct columns: shapes n=500 `metal=6.5 → direct=2.8 (5.0× vs CPU)`, n=1500 `8.6 → 3.6 (4.3×)`; mixed n=500 `10.7 → 5.2 (5.9×)`, n=1500 `19.9 → 9.8 (3.7×)` — **removing the read-back roughly halves the Metal frame time** (≈3.7–5.9× faster than CPU).

> **GPU content + editor integration (follow-up PR).** Moved the rest of the scene onto the GPU and wired the direct path into the editor. **Dashed/dotted strokes**: `Tessellator.dashSplit` emits the pattern's "on" runs, stroked as solid pieces. **Images**: rendered as textured quads via a Frame/draw-command model — `SceneGeometry` emits an ordered command list (colored-triangle runs interleaved with images in z-order) and `ImageTextureCache` uploads each decoded image once; a second textured-quad pipeline samples it (crop → UV sub-rect). **Editor hybrid**: when the Metal backend is active on iOS the canvas becomes a `CAMetalLayer` (`EditorMetalCanvas`) presenting GPU shapes/freedraw/dashed/images directly, with a Core Graphics overlay above for **text + selection handles** — text stays on CG so it re-rasterizes per zoom and stays crisp (verified on device, sharp at ~490% zoom). **Text on GPU was deliberately *not* done** via a glyph atlas: a fixed-size atlas pixelates under zoom, contradicting the crisp-text goal; the hybrid's CG overlay keeps it crisp. **Comprehensive benchmark** (every component type — rect solid + dashed, diamond, ellipse, line, arrow, freedraw, image, text), on device 1200×800: `all` n=500 `cpu=11.6 metal=6.6 direct=2.7 hybrid=4.3 (2.7× vs CPU)`, n=1500 `cpu=13.8 metal=10.9 direct=4.1 hybrid=7.3 (1.9×)` — where **hybrid** = the direct GPU frame + the CG text overlay (what the live editor pays). Still deferred: SDF GPU text (if text must leave CG), and GPU dashed-edge antialiasing niceties.

**Sequencing:** A → B → *(measure)* → C → *(measure)* → D. A + B + C delivered the perceived speedup and crisp zoom on CPU; Stage D (Metal) then landed as a runtime-selectable GPU backend behind the CG fallback, for raster-bound workloads and to compare the two renderers on device.

## Phase 8 — Collaboration & cloud
**Goal:** multiplayer across **iOS and web-browser** clients over a **custom WebSocket protocol**.

> **Status: complete (core).** Real-time iPad ↔ browser collaboration is delivered. A shared, byte-identical wire protocol is spoken by both clients — Swift `ExcalidrawCollab` (`CollabMessage`, `Reconcile`, `CollabCodec`, `CollabClient`) and TypeScript `@xs/protocol` + `@xs/svelte` `CollabSession` — locked by the `Fixtures/protocol/*.json` corpus both test suites assert against. A Node relay (`web/server/`) handles rooms, presence, and an in-memory scene snapshot; the existing `version`/`versionNonce` reconciliation resolves concurrent edits identically on both sides. `EditorModel` joins a room (broadcast local edits, apply remote reconciled without polluting undo, presence/cursors, auto-reconnect). **Validated end-to-end:** the real SwiftUI app in an iOS simulator and a real browser join one room and converge live — automated by `web/scripts/collab-live.sh` (XCUITest `CollabLiveUITests` + Playwright). The TypeScript + Svelte 5 twin (the web client) is its phase T7 — see **[docs/TYPESCRIPT_SVELTE_PORT.md](TYPESCRIPT_SVELTE_PORT.md)**.
> **Deferred:** durable/Redis relay persistence (snapshot is in-memory), end-to-end encryption, and follow mode.

> **Generators shipped (additive, no architecture change):** group-aware selection; **tables** (a grid of container-bound text cells, add row/column, edit via double-tap); **charts** (bar/line from a number series, via a values-input sheet) — both emit standard grouped elements and round-trip through `.excalidraw`. **Remaining from this group:** Mermaid → diagram (a text→elements parser; Swift flowchart-subset or JSC-embedded mermaid.js).

---

## Known gaps & deferred items

The single source of truth for what's **not** yet implemented, kept in sync with the code. Phases 0–7 + tables/charts + Phase 7.5 rendering acceleration are complete, and most of the original long tail has since shipped (Mermaid, embeddables, PNG re-open, pickers, laser/eraser, fonts infra, Apple Pencil, Files/autosave — see **Recently closed** below). 572 tests, ~92% logic coverage, CI green; everything still listed is deliberately deferred, not forgotten.

**Still deferred**
- **Collaboration & cloud** (Phase 8) — core real-time multiplayer (iPad ↔ browser, presence, cursors, reconnect) is **done** (see Phase 8 above). Still deferred: durable/Redis relay persistence, end-to-end encryption, and follow mode.
- **Bundled font files** — the loading + family mapping is wired (`FontRegistry`), but the licensed Excalidraw font files (Excalifont/Virgil/Comic Shanns…) aren't committed; dropping them into the app bundle takes effect, otherwise text uses system fallbacks (Bradley Hand / Helvetica / Menlo). Exact Core Text metric parity also remains.
- **Hand-drawn parity** — hachure fill and perfect-freehand outlines are visually faithful but not line-identical to upstream (scan-line/edge handling differs).
- **GPU text** — text stays on the Core Graphics overlay by design (a fixed-size glyph atlas pixelates at zoom; SDF GPU text is a future option); the GPU pass repaints the full viewport (ignores the incremental-redraw `clip`).
- **Full `DocumentGroup` browser-on-launch** — the app uses Files-app open/save + autosave + recents instead, to keep the single-editor shell; a browser-on-launch would replace it.

**Recently closed** (were deferred, now shipped)
- ✅ **Arrowhead-type picker** (start/end) and **custom color picker** (native iOS picker includes the screen eyedropper).
- ✅ **Laser pointer** + animated eraser trail (fading-trail overlay).
- ✅ **PNG scene-embed round-trip** — exported PNGs carry the scene (a `tEXt` chunk) and re-open as editable drawings.
- ✅ **Mermaid → diagram** — `MermaidParser` (flowchart subset → shapes + bound labels + arrows, layered layout).
- ✅ **Live embeddables** — `WKWebView` over allow-listed hosts (`EmbedAllowList`), interactive except under the selection tool.
- ✅ **Files open/save + autosave + recents** — `fileImporter`/`fileExporter` + a `DocumentStore` autosave slot and security-scoped recents.
- ✅ **Font-loading infrastructure** — `FontRegistry` registers bundled fonts + maps families (assets pending).
- ✅ **Apple Pencil hover** (17.5+) + **Pencil Pro squeeze** (`UIHoverGestureRecognizer` + `UIPencilInteraction`).
- ✅ **Retained-layer / Metal renderer** — Phase 7.5 (above): layered split, gesture snapshots, runtime-selectable Metal GPU backend with the direct-to-`CAMetalLayer` editor hybrid.
- ✅ **Golden-image render tests** — committed pixel references (`Tests/ExcalidrawRenderTests/Golden/`).

**Collab-oriented model internals** (built lean until Phase 8)
- Full rocicorp fractional-indexing edge cases + legacy binding-v1 migration; property-level partial deltas & AppState history.

---

## Sequencing rationale
- **Phases 0–3 close the vertical slice** and de-risk the two scariest unknowns early: rough.js fidelity (Phase 2) and the raw-touch interaction layer (Phase 3).
- **File-format fidelity is front-loaded** (Phase 1) so every later phase reads/writes real Excalidraw files.
- **Hard algorithms (elbow A*, Newton intersect) are deferred** (Phase 7) behind the features that don't need them, so they never block a shippable build.
- **Collaboration is last and optional** but the data model (deltas, fractional indices, version nonces) is built collaboration-ready from Phase 1.
