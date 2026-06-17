# Excalidraw-Swift

A native iOS (iPhone + iPad) port of [Excalidraw](https://excalidraw.com) in Swift / SwiftUI, aiming for feature parity with the web app, first-class Apple Pencil support, and finger-friendly UX.

> Status: **feature-complete for single-user editing** (roadmap Phases 0–7 done, plus tables & charts, plus Phase 7.5 rendering acceleration incl. a Metal GPU backend). Runs on the iPhone + iPad simulators and device. 534 tests passing, ~94% logic coverage, CI green. Remaining work is collaboration (Phase 8, optional) and a set of tracked gaps — see **[Known gaps](#known-gaps)** below and the consolidated list in [docs/ROADMAP.md](docs/ROADMAP.md#known-gaps--deferred-items).

## What works today
- **Drawing & tools:** rectangle, diamond, ellipse, line, arrow (incl. **elbow/orthogonal** arrows with draggable fixed segments), freedraw (pressure), text, image, eraser, hand, frames, **sticky notes**, **tables**, **charts** (bar/line).
- **Hand-drawn rendering:** `RoughKit` (rough.js port, numeric parity validated), all fill styles, **sloppiness** (architect/artist/cartoonist), sharp/round edges, splined multi-point lines, rounded rectangles.
- **Rendering backends:** Core Graphics (default) + an optional **Metal GPU renderer** (`ExcalidrawMetal`), runtime-switchable via a footer toggle with automatic CG fallback. Layered static/dynamic split + gesture snapshots keep the CPU path smooth; the GPU path tessellates shapes/freedraw/dashed strokes/images and (in the editor) presents direct-to-`CAMetalLayer` with a CG overlay for crisp text. An in-app benchmark screen compares CPU vs Metal vs Direct vs the editor hybrid across every component type. See [Phase 7.5](docs/ROADMAP.md#phase-75--rendering-acceleration--performance).
- **Editing:** select/multi-select, group-aware selection, move/resize/rotate, **font scales on resize**, undo/redo, copy/paste, z-order, align, flip, group/ungroup, lock, duplicate.
- **Smart features:** object + gap snapping, arrow↔shape binding, **freehand shape recognition** ("Snap to Shape": rectangle/ellipse/diamond/triangle/line/pentagon/hexagon/star/heart/cloud/speech-bubble, hold-to-snap), flowchart node spawning, interactive image crop, element hyperlinks.
- **Platform:** size-class-adaptive iPhone/iPad UI, dark mode, zen mode, command palette, hardware-keyboard shortcuts, two-finger pan/zoom, palm rejection, localization infra (en/es/ar incl. RTL).
- **Generators & embeds:** **Mermaid → diagram** (paste a flowchart), **live web embeddables** (`WKWebView` behind a host allow-list), tables, charts, sticky notes, flowchart nodes.
- **Tools & polish:** arrowhead-type picker, custom color picker (+ system eyedropper), **laser pointer** + animated eraser trail, Apple Pencil hover (17.5+) & Pencil Pro squeeze.
- **Files:** `.excalidraw` / `.excalidrawlib` round-trip; Files-app open/save + **autosave + recents**; **PNG scene-embed round-trip** (re-open a drawing from its exported PNG); PNG & SVG export; on-disk library.

<a name="known-gaps"></a>
## Known gaps (not yet implemented)
Tracked deferrals, in sync with the code. Full detail in [docs/ROADMAP.md](docs/ROADMAP.md#known-gaps--deferred-items). Most of the original long tail (Mermaid, embeddables, PNG re-open, pickers, laser/eraser, fonts infra, Pencil, Files/autosave) is now shipped — see [Recently closed](#recently-closed).
- **Collaboration / cloud** (Phase 8) — multiplayer, presence, cursors (data model is collab-ready).
- **Fidelity** — the **bundled Excalidraw font files** themselves aren't committed (loading + family mapping is wired, so dropping the `.ttf/.otf` into the app bundle takes effect; until then text uses system fallbacks). Hachure fill and perfect-freehand outlines are visually faithful, not line-identical.
- **Rendering** — text stays on the Core Graphics overlay by design (a GPU glyph atlas would pixelate at zoom; SDF GPU text is a possible future option); the GPU path repaints the full viewport (ignores the incremental-redraw `clip` — idempotent, perf-only).
- **Documents** — uses Files-app open/save (`fileImporter`/`fileExporter`) + autosave + recents rather than a full `DocumentGroup` browser-on-launch (which would replace the single-editor shell).

<a name="recently-closed"></a>
### Recently closed
Arrowhead-type picker · custom color picker + eyedropper · laser pointer + animated eraser trail · **PNG scene-embed round-trip** (re-open a drawing from an exported PNG) · **Mermaid → diagram** parser · **live `WKWebView` embeddables** (host allow-list) · Files-app open/save + autosave + recents · **font-loading infrastructure** · **Apple Pencil hover** (17.5+) + Pencil Pro squeeze · Metal GPU renderer (Phase 7.5).

## Design decisions
- **Rendering:** SwiftUI `Canvas` + Core Graphics (static scene + interactive overlay), with a Swift port of rough.js (`RoughKit`) for the hand-drawn look; an optional Metal GPU backend (`ExcalidrawMetal`) is swappable at runtime behind a `SceneRendering` protocol, with CG as the default and automatic fallback.
- **Minimum OS:** iOS 17+ (`@Observable`, mature Canvas, Apple Pencil hover on 17.5+).
- **Delivery:** vertical-slice-first — a thin end-to-end path early, then widen.
- **Quality:** >90% test coverage, golden-image render tests, XCUITest e2e on iPhone + iPad.
- **Compatibility:** `.excalidraw` / `.excalidrawlib` round-trip with excalidraw.com.

## Documents
- **[docs/INVESTIGATION.md](docs/INVESTIGATION.md)** — analysis of the upstream source: data model, file format, rendering pipeline, interaction model, geometry/math, and full feature inventory.
- **[docs/PLAN.md](docs/PLAN.md)** — architecture, Swift package structure, key design decisions, testing strategy, risks.
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — phased delivery plan (Phase 0 foundations → Phase 8 collaboration), with per-phase status and a consolidated **[Known gaps & deferred items](docs/ROADMAP.md#known-gaps--deferred-items)** list.

## Building

Open **`ExcalidrawSwift.xcodeproj`** and run the `ExcalidrawApp` scheme. The
project is committed to the repo (it's generated from `project.yml` via
[XcodeGen](https://github.com/yonsm/XcodeGen) but kept in git so it's stable).
The libraries also build and test without Xcode via `swift build` / `swift test`.

Regenerate the project only after changing `Package.swift` (targets/products)
or `project.yml`, then commit the result:

```sh
brew install xcodegen        # once
./scripts/generate.sh        # regenerate + clear stale caches
```

If Xcode ever reports **"Missing package product"** or **"Couldn't load
project"**, it's stale package state: run `./scripts/generate.sh` (it clears
`.swiftpm` and this project's DerivedData), then **quit and reopen**
`ExcalidrawSwift.xcodeproj` — open the `.xcodeproj`, not the folder or
`Package.swift`.

## Architecture at a glance
Layered, framework-light core (pure Swift, simulator-independent) under a thin SwiftUI shell:

`ExcalidrawMath` → `ExcalidrawModel` → `ExcalidrawGeometry` · `RoughKit` · `FreehandKit` → `ExcalidrawRender` → `ExcalidrawMetal` · `ExcalidrawEditor` → `ExcalidrawUI` → `ExcalidrawApp`

(`ExcalidrawEditor` is the pure, UIKit-free editor state machine — tools, selection/transform, undo, and all the generators/algorithms — bridged to SwiftUI by `ExcalidrawUI`'s `EditorModel`. `ExcalidrawMetal` is the optional GPU renderer — scene→triangle tessellation, an image texture cache, and the `CAMetalLayer` present path — behind the same `SceneRendering` protocol as the Core Graphics `SceneRenderer`.)

See [PLAN.md §2](docs/PLAN.md) for details.
