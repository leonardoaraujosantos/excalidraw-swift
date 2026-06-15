# Excalidraw Source Investigation

> Snapshot of the upstream Excalidraw monorepo (`~/work/excalidraw`, commit `28a9b171`) as the basis for the native Swift/SwiftUI port. ~116K LOC of TypeScript across well-separated packages.

## 1. Repository map

| Package | Role | Files | LOC | Port relevance |
|---|---|---|---|---|
| `packages/math` | Geometry primitives (point, vector, line, segment, curve, ellipse, polygon, angle) | 16 | ~2.0K | **Port 1:1** — pure functions, deterministic |
| `packages/element` | Element model, bounds, collision, binding, resize, linear editor, shape generation, store/delta | 50 | ~31K | **Core port** — the engine |
| `packages/common` | Constants, colors, keys, points, utils, emitter | 20 | ~3.7K | Port selectively |
| `packages/excalidraw` | React app: renderer, App.tsx interaction controller, UI components, actions, fonts, data I/O | 340 | ~78K | Behavior reference; UI reimplemented in SwiftUI |
| `packages/utils` | Export (PNG/SVG) | 4 | ~0.8K | Port export logic |
| `packages/fractional-indexing` | Ordering keys for collab/z-index | 2 | ~0.3K | Port if collab/stable ordering needed |
| `excalidraw-app/` | Hosting app, collaboration (Firebase/WebSocket), persistence | — | — | Out of scope for v1 |

Key external JS libraries that have **no Swift equivalent and must be reimplemented**:
- **roughjs** (4.6.4) — the hand-drawn look. Seed-based stroke perturbation. *Critical.*
- **perfect-freehand** (1.2.0) — pressure-aware freehand stroke outlines.
- **points-on-curve** — Bézier sampling (trivial to port).

## 2. Data model

### 2.1 Element base (all elements)
`id, x, y, width, height, angle (radians), strokeColor, backgroundColor, fillStyle (hachure|cross-hatch|solid|zigzag), strokeWidth, strokeStyle (solid|dashed|dotted), roundness ({type, value?}|null), roughness (0|1|2), opacity (0–100), seed (int, drives rough randomness), version, versionNonce, index (FractionalIndex|null), isDeleted, groupIds[], frameId (string|null), boundElements ([{id,type:"arrow"|"text"}]|null), updated (epoch ms), link (string|null), locked, customData?`

### 2.2 Per-type fields
- **rectangle / diamond / ellipse** — base only.
- **text** — `fontSize, fontFamily (enum), text, originalText, textAlign, verticalAlign, containerId|null, autoResize, lineHeight (unitless)`.
- **freedraw** — `points: [LocalPoint], pressures: [number], simulatePressure`.
- **line / arrow** — `points: [LocalPoint], startBinding/endBinding (FixedPointBinding|null), startArrowhead/endArrowhead (Arrowhead|null), polygon`. Arrow adds `elbowed`, and when elbowed `fixedSegments, startIsSpecial, endIsSpecial`.
- **image** — `fileId|null, status (pending|saved|error), scale ([sx,sy] flip), crop (ImageCrop|null)`.
- **frame / magicframe** — `name|null` (containers; children reference via `frameId`).
- **embeddable / iframe** — embedded content; iframe carries `customData.generationData`.
- **selection** — ephemeral, never persisted.

`LocalPoint = [Double, Double]` relative to element `x/y`. Arrowheads include modern (`arrow, bar, circle(_outline), triangle(_outline), diamond(_outline)`) and cardinality variants. `FixedPointBinding = {elementId, fixedPoint:[0–1,0–1], mode: inside|orbit|skip}`.

### 2.3 File format (`.excalidraw`, MIME `application/vnd.excalidraw+json`)
```jsonc
{ "type":"excalidraw", "version":2, "source":"<origin>",
  "elements":[...],            // includes isDeleted:true (soft deletes)
  "appState":{...},            // subset; export keeps gridSize/step/mode, viewBackgroundColor, lockedMultiSelections
  "files":{ "<fileId>": {mimeType,id,dataURL,created,lastRetrieved?,version?} } }
```
`restore.ts` is the **compatibility contract**: generates missing fractional indices, repairs text-container refs, migrates binding v1→v2, normalizes points/dimensions, drops empty text, clamps oversized arrows (>75k px). The port must replicate `restore.ts` for round-trip fidelity. `.excalidrawlib` is the library format.

### 2.4 AppState (~85 fields)
Grouped concerns: **viewport** (zoom 0.1–30, scrollX/Y, width/height, viewBackgroundColor, viewModeEnabled); **active tool** (type, locked, lastActiveTool, penMode/penDetected); **selection/interaction** (selectedElementIds, hovered, groups, editingGroupId, selectedLinearElement, newElement, resizing/rotating flags); **current item styles** (stroke/bg/fill/width/style/roughness/roundness/opacity/font*/arrowheads/arrowType) applied to new elements; **binding & snapping** (isBindingEnabled, suggestedBinding, grid size/step/mode, objectsSnapMode, snapLines); **frames** (frameRendering {enabled,name,outline,clip}); **UI** (openDialog/Menu/Popup/Sidebar, contextMenu, toast, theme, zenMode); **export** (background, scale 1–3, embedScene, darkMode); **collab** (collaborators map — later phase).

### 2.5 Versioning, ordering, history
- `version` (monotonic per element) + `versionNonce` (random tiebreak) for reconciliation.
- `index` is a **fractional index string** for deterministic z-order across clients; `null` until first save.
- **Store/Delta/History**: `Delta = {deleted: Partial<T>, inserted: Partial<T>}`, replayable. Store emits durable (undoable) vs ephemeral increments; history keeps undo/redo stacks of deltas. `CaptureUpdateAction` = IMMEDIATELY | EVENTUALLY | NEVER controls snapshotting.

### 2.6 Swift representation notes
- TS discriminated unions → **`enum ExcalidrawElement` with associated values**, or a base struct + per-type payload. Custom `Codable` for the JSON contract (unions, arrowhead strings, fractional index).
- Branded types (`FractionalIndex`, `FileId`, `Radians`, `LocalPoint`) → lightweight wrappers or typealiases.
- Excalidraw **mutates elements in place** (`mutateElement`); Swift port should use value types with copy-on-write and an explicit mutation/versioning helper that bumps `version`/`versionNonce`/`updated`.
- Graph integrity (arrow↔shape bindings, text↔container, element↔frame) needs indexed lookups + load-time repair (port of `restore.ts`).

## 3. Rendering pipeline

**Two-canvas model**: a **static** layer (elements + grid, throttled to RAF) and an **interactive** layer (selection box, transform handles, snap lines, remote cursors, laser/eraser trails) drawn on top. The Swift port maps this directly to a SwiftUI `Canvas` for static content + an overlay `Canvas`/layer for interactive UI.

**Per-element flow**: `ShapeCache.generateElementShape(element)` (memoized in a WeakMap) → rough.js `RoughGenerator` produces a `Drawable` (rectangle/ellipse/polygon/linearPath/curve/path) → `roughCanvas.draw()` emits canvas ops. Freedraw and text bypass rough.js (Path2D fill / `fillText`). Images use cached bitmaps with optional rounded-rect clip.

**rough.js essentials to port**: deterministic seeded RNG (`element.seed`), per-vertex perturbation, fill styles (hachure/cross-hatch/solid/zigzag → hatching line generation), `strokeLineDash` for dashed `[8,8+w]` / dotted `[1.5,6+w]`, `roughness` adjusted down for small elements, `preserveVertices`. This is the visual identity — budget real effort here.

**Coordinate system**: scene coords → apply `zoom` (global `scale`) and `scrollX/Y` (per-element translate) → device pixels (`devicePixelRatio`). Rotation applied per element around its center. Maps cleanly to `CGAffineTransform`.

**Text**: `getFontString` → measure via canvas `measureText` (advance width), per-character width cache, line wrapping, vertical baseline offset per font (`FONT_METADATA` ascent/descent/lineGap). Swift port uses **Core Text** (`CTLine`/`CTFramesetter`) and must bundle the Excalidraw fonts (Excalifont default, Virgil, Cascadia, Nunito, Comic Shanns, Liberation, etc.) to match metrics.

**Arrows**: main path (linearPath | curve | elbow SVG path with rounded corners) + arrowhead shapes computed from the rendered curve endpoint + perpendicular.

**Export**: canvas → PNG/JPEG blob; SVG via RoughSVG with decimal precision. PNG can embed the scene for round-trip. Port targets `UIGraphicsImageRenderer`/`CGContext` for raster and a string-built SVG for vector.

**Biggest rendering challenges**: (1) rough.js port incl. fills, (2) Core Text metrics matching JS measurements, (3) perfect-freehand outline port, (4) elbow-arrow corner rendering, (5) frame clipping, (6) dark-mode color filter.

## 4. Interaction model

`App.tsx` (~414K) is one big pointer state machine around a `PointerDownState`: **pointerdown → throttled pointermove → pointerup**, dispatching on the active tool into states: idle, drawing (shape/linear/freedraw), dragging, resizing, rotating, box/lasso selecting, panning, text editing.

**Tools**: selection, lasso, hand/pan, rectangle, diamond, ellipse, arrow, line, freedraw, text, image, eraser, laser, frame, embeddable, magicframe.

**Transform handles are pointer-type aware** (`mouse:8, pen:16, touch:28` px in scene coords) — directly relevant for finger vs Pencil UX. Phones limit resize to corners.

**Linear editing**: points normalized so start = `[0,0]`; midpoint insertion, per-point drag, multi-click creation with `LINE_CONFIRM_THRESHOLD=40px`, loop close detection.

**Binding**: arrows bind to shapes within `maxBindingDistance` (gap `BASE_BINDING_GAP=5`, clamped 15–30 / zoom); suggested binding highlighted on hover; `FixedPointBinding` with focus point and mode.

**Snapping**: object snap (point + gap snaps, `SNAP_DISTANCE=8/zoom`) and grid snap (`getGridPoint`, default grid 20).

**Eraser / laser / lasso** use an `AnimatedTrail` with decay (eraser 200ms, laser 1000ms); eraser does intersection tests and supports retrace-to-restore.

**Gestures**: two-finger pinch-zoom + pan via tracked pointer map; double-tap (≤400ms, ≤35px) to edit text; pressure from `event.pressure` (0–1) stored per freedraw point; **pen mode** auto-enabled on stylus input, which then rejects stray touch input (palm rejection) except selection/lasso/text/image.

**iOS mapping**: pinch/pan/long-press/double-tap → gesture recognizers or SwiftUI gestures; `UITouch.force` → pressure; `touchType == .pencil` vs `.direct` → palm rejection; Apple Pencil hover (17.5+) → preview; drag threshold (`DRAGGING_THRESHOLD≈10px`) to distinguish tap from drag. Most of the *logic* ports; the *event source* is rebuilt on UIKit/SwiftUI.

## 5. Geometry & math (the hard algorithms)

- **Primitives** (`packages/math`): point/vector ops, segment intersection (parametric + cross product), line/ellipse/polygon, angle normalization, ranges. Straightforward 1:1 port.
- **Bounds** (`bounds.ts`): per-type AABB incl. rotated corners; ellipse via effective semi-axes; cubic-Bézier bbox via derivative roots; curve sampling (`pointsOnBezierCurves`, ellipse 90 pts). Cached by version.
- **Hit testing** (`collision.ts`, `distance.ts`): rotated-bounds early-out → point-in-element via **ray casting (odd-even)** for filled shapes, distance-to-outline for strokes. Element decomposed into sides + corner curves. Ellipse distance via 3-iteration Newton.
- **Curve↔line intersection**: Newton–Raphson with analytical Jacobian, multiple initial guesses. Non-trivial.
- **Arc length**: Legendre–Gauss quadrature (n=24) with precomputed nodes/weights.
- **Catmull-Rom → Bézier** (tension 0.5) for smooth lines/arrows; curve offset for parallel curves.
- **Elbow arrows** (`elbowArrow.ts`, `heading.ts`, ~2K LOC): cardinal **heading** detection (cone tests for diamonds), dynamic AABB computation, **A\* grid routing** with Manhattan + bend-penalty heuristic and binary heap, fixed-segment constraints, short-segment cleanup. The single most complex algorithm — defer to a later phase.

**Port priority**: math primitives + bounds + hit testing are foundational (early). Newton-based intersection, Legendre-Gauss, and elbow A* are advanced and can land later behind feature flags.

## 6. Feature inventory (by phase intent)

**MVP / core**: pan/zoom canvas; tools (selection, rect, diamond, ellipse, arrow, line, freedraw, text, image, eraser); properties (stroke/bg color, width, fill style, stroke style, roundness, opacity, font family/size/align); multi-select, move, resize, rotate; group/ungroup; duplicate/delete; align/distribute/flip; z-order; undo/redo; copy/paste; `.excalidraw` save/load; PNG/SVG export; dark mode; grid; snapping.

**Important (phase 2+)**: library (`.excalidrawlib`); local persistence + autosave; image insert/crop; context menu (long-press); command palette / shortcuts; binding; linear midpoint editing; mobile bottom toolbar + bottom-sheet properties; form-factor adaptation (phone ≤599 / tablet 600–1180 / desktop); pen mode & Pencil; stats panel; element linking; frames.

**Advanced**: collaboration (WebSocket/Firebase), Mermaid-to-diagram, charts from spreadsheet, embeddables/iframes, AI/magic features, flowchart auto-layout. Most are later/optional for iOS.

**Localization**: 61 locales upstream, with RTL. v1 can ship English + a few, with infra for the rest.

## 7. Key file references
- Model/types: `packages/element/src/types.ts`, `packages/excalidraw/types.ts`, `appState.ts`
- File I/O: `packages/excalidraw/data/{restore,types,json,blob}.ts`
- Shape gen / rough: `packages/element/src/{shape,renderElement}.ts`
- Renderers: `packages/excalidraw/renderer/{staticScene,interactiveScene,staticSvgScene,helpers}.ts`
- Interaction: `packages/excalidraw/components/App.tsx`
- Geometry: `packages/math/src/*`, `packages/element/src/{bounds,collision,distance,binding,linearElementEditor,elbowArrow,heading,resizeElements,selection}.ts`
- Text/fonts: `packages/element/src/textMeasurements.ts`, `packages/excalidraw/fonts/*`
- Export: `packages/utils/src/export.ts`
- History/store: `packages/excalidraw/history.ts`, `packages/element/src/{store,delta}.ts`
