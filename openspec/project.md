# Project Context

Native iOS (iPhone + iPad) port of [Excalidraw](https://excalidraw.com) in Swift / SwiftUI, aiming for feature parity with the web app, first-class Apple Pencil support, and finger-friendly UX. These baseline specs were reverse-engineered from the existing, feature-complete single-user codebase (README + docs/ROADMAP Phases 0–7.5) and describe **observed behavior**, not proposals. Future work flows through normal OpenSpec changes against this baseline.

## Stack & constraints

- **Language / UI:** Swift, SwiftUI. Minimum target **iOS 17+** (`@Observable`, mature `Canvas`, Apple Pencil hover on 17.5+).
- **Module graph (framework-light core, simulator-independent):** `ExcalidrawMath` → `ExcalidrawModel` → `ExcalidrawGeometry` · `RoughKit` · `FreehandKit` → `ExcalidrawRender` → `ExcalidrawMetal` · `ExcalidrawEditor` → `ExcalidrawUI` → `ExcalidrawApp`. `ExcalidrawEditor` is the pure, UIKit-free editor state machine; `ExcalidrawUI` bridges it to SwiftUI via `EditorModel`.
- **Rendering:** Core Graphics `SceneRenderer` is the default; an optional Metal GPU backend (`ExcalidrawMetal`) is swappable at runtime behind the `SceneRendering` protocol, with automatic CG fallback.
- **Compatibility:** `.excalidraw` / `.excalidrawlib` round-trip with excalidraw.com (schema version 2).
- **Quality gates:** >90% logic coverage (currently ~92%, 572 tests), golden-image render tests, XCUITest e2e on iPhone + iPad, SwiftLint `--strict`, SwiftFormat.
- **Build:** Xcode project (`ExcalidrawSwift.xcodeproj`) generated from `project.yml` via XcodeGen but committed; libraries also `swift build` / `swift test` headless.

## Capability map

| Spec | Covers |
|------|--------|
| `data-model` | Element schema, scene, app state, document envelope, versioning, fractional indexing |
| `file-format` | `.excalidraw` / `.excalidrawlib` JSON round-trip, lenient restore, library store |
| `geometry-and-math` | Points/vectors/angles, bounds, hit-testing, intersections, curves, snapping, culling |
| `editing-history` | Diff-based undo/redo, transactional store |
| `hand-drawn-rendering` | RoughKit (rough.js port, fills, sloppiness, seeded RNG), FreehandKit pressure outlines |
| `scene-rendering` | Core Graphics renderer, layered caching, text layout, fonts, images, frames, overlay |
| `metal-rendering` | GPU backend, tessellation, caches, MSAA, direct-to-drawable, editor hybrid, benchmarks |
| `drawing-tools` | Tool model and element creation (shapes, freedraw, text, image, eraser, hand, frame) |
| `selection-and-transform` | Select, move/resize/rotate, group/align/flip/z-order/lock/duplicate, copy/paste, linear edit, crop |
| `arrows-and-bindings` | Arrow↔shape binding, elbow routing with pinnable segments, arrowheads |
| `smart-features` | Object/gap snapping, freehand shape recognition, hold-to-snap, flowchart spawning, hyperlinks |
| `generators` | Mermaid flowcharts, tables, charts, sticky notes |
| `persistence` | Autosave, recents, Files open/save, PNG scene-embed round-trip, PNG/SVG export |
| `platform-ux` | Adaptive layout, theming, zen mode, command palette, shortcuts, localization/RTL, Pencil, trails, pickers, zoom, web embeds |

## Known gaps & deferred behavior (intentionally NOT in the baseline)

These are tracked deferrals; new changes proposing them should be scoped against the relevant spec above. See README "Known gaps" and `docs/ROADMAP.md`.

- **Collaboration / cloud (Phase 8):** multiplayer, presence, cursors. The data model is collab-ready but no realtime/sync capability exists.
- **Bundled fonts:** font-loading + family mapping is wired (`scene-rendering`), but the Excalidraw `.ttf/.otf` font files themselves are not committed; text falls back to system fonts until they are dropped into the bundle.
- **GPU text:** by design, text is never tessellated to the GPU; it stays on the Core Graphics overlay to remain crisp at any zoom (`metal-rendering` non-goal). An SDF GPU-text path is a possible future option.
- **GPU incremental redraw:** the Metal path repaints the full visible region each frame, ignoring the incremental-redraw `clip` (idempotent, perf-only).
- **Document browser:** uses Files-app `fileImporter`/`fileExporter` + autosave + recents rather than a full `DocumentGroup` browser-on-launch (`persistence` non-goal).
- **Render fidelity:** hachure fill and perfect-freehand outlines are visually faithful but not line-identical to the web app.

## Conventions for changes

- Keep the model wire-compatible with `.excalidraw` v2; preserve unmodelled fields via `customData` / `AppState`.
- Any bug fix ships with a regression test (project rule).
- Verify claims against `main` before asserting pre-existing behavior.
