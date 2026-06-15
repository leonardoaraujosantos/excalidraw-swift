# Excalidraw-Swift — Technical Plan

Native iOS (iPhone + iPad) Excalidraw clone in Swift / SwiftUI, targeting feature parity with the upstream web app, first-class Apple Pencil support, and finger-friendly UX. **Decisions locked:** SwiftUI `Canvas` + Core Graphics rendering; **iOS 17+**; vertical-slice-first delivery; **>90% test coverage**; e2e UI tests on iPhone + iPad.

See [INVESTIGATION.md](./INVESTIGATION.md) for the source analysis this plan rests on, and [ROADMAP.md](./ROADMAP.md) for the phased schedule.

## 1. Goals & non-goals

**Goals**
- Faithful hand-drawn rendering (rough.js parity) and `.excalidraw` / `.excalidrawlib` round-trip compatibility with excalidraw.com.
- Full local editing experience: all core element types, tools, properties, selection/transform, undo/redo, export.
- Touch + Apple Pencil: pressure, hover (17.5+), palm rejection, pinch-zoom/pan, adaptive hit targets.
- Adaptive UI for iPhone (compact, bottom toolbar + sheets) and iPad (regular, side panels, keyboard shortcuts).
- >90% unit/logic coverage; deterministic golden-image render tests; XCUITest e2e flows.

**Non-goals (v1)**
- Real-time collaboration backend (architect for it; don't ship it).
- AI/magic features, Mermaid, spreadsheet charts, embeddables (later phases).
- Full 61-locale localization at launch (infra only + English).

## 2. Architecture overview

Layered, framework-light core so logic is portable and testable independent of SwiftUI.

```
┌──────────────────────────────────────────────────────────┐
│ App (SwiftUI)  — scenes, document browser, settings        │
├──────────────────────────────────────────────────────────┤
│ UI layer (SwiftUI)                                         │
│  • CanvasView (static Canvas + interactive overlay Canvas) │
│  • Toolbar / PropertiesPanel / ContextMenu / Dialogs       │
│  • Adaptive layout (size classes: compact vs regular)      │
├──────────────────────────────────────────────────────────┤
│ Interaction layer                                          │
│  • PointerController (state machine) + GestureCoordinator  │
│  • Tool handlers, Selection/Transform, Snapping, Binding   │
├──────────────────────────────────────────────────────────┤
│ Render layer                                               │
│  • SceneRenderer (CG) • RoughKit (rough.js port)           │
│  • FreehandKit (perfect-freehand) • TextLayout (Core Text) │
│  • ShapeCache • Exporter (PNG/SVG)                          │
├──────────────────────────────────────────────────────────┤
│ Domain core (pure Swift, no UIKit/SwiftUI)                 │
│  • ExcalidrawElement model + AppState                      │
│  • Scene (element store, indices, graph integrity)         │
│  • Store/Delta/History (undo/redo)                         │
│  • Geometry (MathKit) • bounds/collision/distance          │
│  • Persistence (restore.ts port, Codable, files store)     │
└──────────────────────────────────────────────────────────┘
```

### Swift package structure (SwiftPM, app thin-shells the libs)
- **`ExcalidrawMath`** — port of `packages/math` (+ Legendre-Gauss, Newton intersect). Pure, no deps.
- **`ExcalidrawModel`** — element enum/structs, AppState, Scene, Store/Delta/History, fractional index. Codable.
- **`ExcalidrawGeometry`** — bounds, collision, distance, binding, linear editor, elbow routing. Depends on Math + Model.
- **`RoughKit`** — seeded RNG + drawable generation + fill styles. Renders into a `GraphicsContext`/`CGContext`. No Model dep (takes geometry inputs).
- **`FreehandKit`** — perfect-freehand outline port.
- **`ExcalidrawRender`** — SceneRenderer, ShapeCache, TextLayout (Core Text), Exporter. Depends on Model/Geometry/RoughKit/FreehandKit.
- **`ExcalidrawUI`** — SwiftUI views, interaction controllers, view models.
- **`ExcalidrawApp`** — app target, document model, file browser.

This separation keeps ~80% of the code (everything below the UI layer) unit-testable without a simulator, which is how we hit >90% coverage credibly.

## 3. Key design decisions

### 3.1 Element model
`enum ExcalidrawElement` with associated value structs per type, sharing a `BaseProperties` struct. Conform to a `CanvasElement` protocol exposing `id, transform, bounds(), version`. Custom `Codable` to match the JSON wire format exactly (string-keyed enums for tool/fill/stroke/arrowhead; `[Double]` point arrays; soft-deleted elements preserved). Value semantics + COW; a `mutate(_:)` helper bumps `version/versionNonce/updated`.

### 3.2 Scene & integrity
`Scene` holds elements in order with: id→element map, frame→children index, container→boundText, element→bindings. A `restore(_:)` entrypoint mirrors `restore.ts`: assign missing fractional indices, repair refs, migrate bindings, clamp/normalize. All load paths go through it.

### 3.3 Rendering (SwiftUI Canvas + CG)
- **Static `Canvas`**: applies `CGAffineTransform` (scroll → zoom → dpr handled by Canvas), iterates visible (frustum-culled) elements front-to-back, pulls a cached drawable from `ShapeCache`, strokes/fills via `GraphicsContext`. Grid drawn first.
- **Interactive overlay `Canvas`**: selection box, transform handles (size by pointer type), snap lines, binding highlight, trails, remote cursors. Redraws on interaction only.
- **RoughKit**: deterministic RNG seeded by `element.seed`; perturbs polylines; generates hachure/cross-hatch/zigzag fill line sets and solid fills; honors dash/dotted, roughness scaling, `preserveVertices`. Output is a `Drawable` (sets of CG paths + style) cached per (element, theme).
- **Text**: `TextLayout` using Core Text; bundle Excalidraw fonts; build a char-advance cache and line wrapper matching `textMeasurements.ts`; validate metrics against fixtures from the JS implementation.
- **ShapeCache**: keyed by element identity+version; invalidated on mutation, theme change, font load. Mirrors upstream WeakMap behavior with an NSCache/dictionary + version guard.

### 3.4 Interaction
A `PointerController` reproduces the `App.tsx` state machine as an explicit Swift `enum State`. Input arrives from a custom `UIView` (via `UIViewRepresentable`) that exposes raw `UITouch` data — needed for `force`, `touchType`, `altitudeAngle`, coalesced/predicted touches, and Pencil hover — because SwiftUI gestures alone don't surface pressure/coalesced touches. A `GestureCoordinator` arbitrates: 1 finger = tool action, 2 fingers = pinch-zoom + pan, long-press = context menu, double-tap = text edit. Pen-mode palm rejection ignores `.direct` touches when a `.pencil` touch is active. Coalesced touches feed freehand for smooth high-rate strokes.

### 3.5 Undo/redo
Port Store/Delta/History. Deltas are property-level diffs; durable increments push undo entries, ephemeral ones don't. `CaptureUpdateAction` controls batching. This also future-proofs collaboration (deltas are the sync unit).

### 3.6 Persistence & documents
`UIDocument`/`FileDocument`-based `.excalidraw` documents integrated with the iOS Files app and document browser. Autosave via document change tracking. Images stored in the files map (base64 data URLs on disk to preserve exact round-trip; optionally externalized for size). `.excalidrawlib` for the library.

### 3.7 Coordinate system
Single source of truth: scene coordinates (Double). A `Viewport` value (`scrollX, scrollY, zoom`) produces `sceneToView`/`viewToScene` transforms. Hit-testing, snapping, and rendering all derive from it. Handle/threshold sizes are specified in view px and divided by zoom for scene-space tests.

## 4. Testing strategy (>90% coverage)

- **Unit tests** (bulk of coverage): Math, Geometry (bounds/collision/distance/binding/elbow), Model Codable round-trips, restore migrations, Store/Delta/History, RoughKit determinism (same seed → same paths), FreehandKit outlines, TextLayout metrics. Port upstream `__tests__` fixtures and `.excalidraw` sample files as golden inputs.
- **Golden-image render tests**: render representative scenes to PNG and compare against committed references with a tolerance (rough.js is deterministic given seed, so output is stable). Catches rendering regressions.
- **Round-trip tests**: load real `.excalidraw` files (incl. older schema versions) → restore → encode → assert structural equality; assert excalidraw.com interop on a corpus.
- **Snapshot tests** for SwiftUI views (size classes: iPhone portrait/landscape, iPad).
- **XCUITest e2e**: scripted flows on iPhone and iPad simulators — draw shape, select/move/resize, edit text, undo/redo, export PNG, save/open document, pinch-zoom. Pencil/pressure paths driven via injectable input where the simulator can't.
- **CI** (GitHub Actions, macOS runner): build all packages, `swift test` + `xcodebuild test` with coverage gating at 90%; golden-image diff artifacts on failure; SwiftLint/format.

## 5. Major risks & mitigations
| Risk | Mitigation |
|---|---|
| rough.js visual fidelity | Port the algorithm faithfully (seeded RNG + perturbation + fills); golden-image tests vs JS-rendered references; isolate in `RoughKit` with its own fixtures. |
| Core Text vs canvas text metrics drift | Bundle exact fonts; build char-advance cache; validate against JS `measureText` fixtures; expose a metrics provider seam like upstream. |
| Elbow-arrow A* complexity | Defer to a later phase behind a flag; ship straight/curved arrows first; port `elbowArrow.ts` with its test fixtures when scheduled. |
| Performance at scale on Canvas | Frustum culling, ShapeCache, throttled static redraw, dirty-region overlay; Metal fallback path kept open if profiling demands it. |
| Pressure/coalesced touches not in SwiftUI | Custom `UIViewRepresentable` exposing raw `UITouch`; coalesced/predicted touches for freehand. |
| File-format round-trip drift | Make `restore` port the single load path; large interop corpus in CI. |

## 6. Definition of done (per feature)
A feature is done when: behavior matches upstream within agreed tolerance; unit tests cover its logic (≥90% lines for the module); a golden-image or snapshot test exists if it renders; an e2e step exists if it's user-reachable; it works on both compact (iPhone) and regular (iPad) size classes; Pencil + touch paths verified.
