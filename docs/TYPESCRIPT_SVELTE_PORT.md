# TypeScript + Svelte 5 Port — Roadmap

A plan to grow a **second implementation** of the Excalidraw-Swift library in TypeScript, with a **Svelte 5** UI shell, so that **iOS and web-browser clients collaborate in real time over a custom WebSocket protocol**.

The Swift app and the TS/Svelte app are *twins*: they share the same data model, the same `.excalidraw` v2 wire format, and — crucially for collaboration — the same element-reconciliation semantics. The [OpenSpec baseline specs](../openspec/specs/) are the **language-neutral contract** both implementations are built against.

---

## Status — ✅ delivered (T0 → T7 complete)

All phases are implemented and green; this document is kept as the historical plan, annotated with what shipped. Built in the `web/` pnpm workspace (tracked on PR #10):

- **`@cyberdynecorp/excalidraw-math · model · geometry · render · editor · svelte · protocol`** + a Node relay **`server/`** (`@cyberdynecorp/excalidraw-relay`), and the **`apps/web`** example exercising every feature.
- **Cross-language parity** enforced in CI: `.excalidraw` round-trip, rough.js op-set parity (TS `roughjs` ⇔ Swift `RoughKit`), canonical-JSON goldens, and byte-identical **protocol** wire fixtures (`Fixtures/protocol/`).
- **Collaboration (T7):** `@cyberdynecorp/excalidraw-protocol` + relay + version/`versionNonce` reconcile + presence/cursors + auto-reconnect; the Swift twin lives in `Sources/ExcalidrawCollab` and speaks a byte-identical protocol. **An iPad simulator and a browser edit one room live**, automated end-to-end by `web/scripts/collab-live.sh` (XCUITest + Playwright + relay).
- **Resolved decisions** (§12): polyglot monorepo here; JSON wire (v1) with sorted-key canonical fixtures (Protobuf deferred); reuse `roughjs`/`perfect-freehand`; Vite SPA; plaintext rooms first (E2E encryption deferred). **Deferred tiers:** `@cyberdynecorp/excalidraw-render-webgl` (WebGL), durable/Redis relay persistence, E2E encryption.

---

## 1. End-state

```
┌──────────────┐         custom WebSocket          ┌──────────────┐
│  iOS / iPad  │◄────────  (rooms, presence, ──────►│ Web browser  │
│  (Swift)     │           element sync)            │ (Svelte 5)   │
└──────┬───────┘                                    └──────┬───────┘
       │  @excalidraw model + version/nonce reconcile      │
       └───────────────── same scene, same fixtures ───────┘
                    relay server (Node, rooms + broadcast)
```

- Both clients open the **same room link**, see each other's **cursors / selection / tool**, and watch elements appear and change live.
- One shared scene; conflicts resolved by the **`version` / `versionNonce` / `updated`** scheme the model already implements (see [`data-model`](../openspec/specs/data-model/spec.md) → "Versioned mutation"). This is the same last-writer-wins-by-version model Excalidraw uses upstream, and it is already in our Swift code — we reuse it on both sides rather than inventing a CRDT.

---

## 2. Guiding principles

1. **Specs are the contract.** Every TS package implements the same `openspec/specs/<capability>/spec.md` requirements the Swift code does. A behavior change goes through OpenSpec once and lands in both implementations.
2. **Reuse proven JS primitives where parity is free.** The Swift project *re-ported* rough.js and perfect-freehand (and validated numeric parity). In TS the originals exist as npm packages — use them, so parity is automatic.
3. **Re-port the project-specific logic** (model codecs, geometry, editor state machine, smart features) so the two clients share *identical* semantics — non-negotiable for collaboration correctness.
4. **Framework-agnostic core, Svelte only at the edge.** Mirror the Swift split: a pure TS core (no DOM) under a thin Svelte 5 runes layer, exactly as `ExcalidrawEditor` (pure) sits under `ExcalidrawUI` (SwiftUI).
5. **Cross-language conformance in CI.** Shared golden fixtures run in *both* test suites so the implementations can't silently drift.

---

## 3. Repository layout (chosen: polyglot monorepo)

**Recommended: polyglot monorepo in this same repo**, so the specs and conformance fixtures are one source of truth.

```
excalidraw-swift-web/            (repo root — keep the name or rename later)
├── Sources/ …               existing Swift packages
├── openspec/specs/ …        shared contract (already exists)
├── fixtures/                NEW — shared golden fixtures (scenes, seeds, expected JSON/SVG)
├── web/                     NEW — pnpm workspace for the TS + Svelte twin
│   ├── packages/
│   │   ├── math/  model/  geometry/  render/  editor/  protocol/
│   │   └── svelte/          Svelte 5 components + runes store
│   ├── apps/web/            the browser app (Vite SPA or SvelteKit)
│   └── server/              Phase 8 WebSocket relay (Node)
└── docs/                    this file
```

Alternative: a separate `excalidraw-web` repo that vendors `fixtures/` + `openspec/specs/` via submodule or npm. Pick monorepo unless release cadences must diverge.

---

## 4. Strategy: reuse vs re-port

| Swift module | TS package | Approach | Notes |
|---|---|---|---|
| `ExcalidrawMath` | `@cyberdynecorp/excalidraw-math` | **Re-port** | Small, pure, deterministic. Curves/splines/angles/vectors. |
| `RoughKit` (rough.js port) | **`roughjs`** (npm) | **Reuse** | Original lib; Swift already validated parity against it → seeds match. |
| `FreehandKit` (perfect-freehand port) | **`perfect-freehand`** (npm) | **Reuse** | Original lib. |
| `ExcalidrawModel` | `@cyberdynecorp/excalidraw-model` | **Re-port** | Element schema, scene, AppState, `.excalidraw`/`.excalidrawlib` codecs, restore, fractional index, history. Must round-trip v2 byte-for-byte with Swift. |
| `ExcalidrawGeometry` | `@cyberdynecorp/excalidraw-geometry` | **Re-port** | Bounds, hit-test, intersections, snapping, culling, frames, **elbow-arrow A\***, shape generation. |
| `ExcalidrawRender` (Core Graphics) | `@cyberdynecorp/excalidraw-render` | **Re-port → Canvas2D** | rough.js draws to canvas natively; text via `measureText`/`Path2D`; image+crop; frames; interactive overlay; layered static/dynamic cache; PNG (with `tEXt` scene-embed) + SVG export. |
| `ExcalidrawMetal` (GPU) | `@cyberdynecorp/excalidraw-render-webgl` | **Defer** | Canvas2D first; a WebGL/WebGPU tier later mirrors the Metal tessellation work. |
| `ExcalidrawEditor` (pure state machine) | `@cyberdynecorp/excalidraw-editor` | **Re-port** | Tools, selection/transform, undo, generators, smart features, arrows/bindings/elbow. No DOM. |
| `ExcalidrawUI` (SwiftUI) | `@cyberdynecorp/excalidraw-svelte` | **Rebuild in Svelte 5** | `EditorModel` → a runes store wrapping `@cyberdynecorp/excalidraw-editor`. |
| `ExcalidrawApp` | `apps/web` | **New** | Vite SPA / SvelteKit host. |
| — (new) | `@cyberdynecorp/excalidraw-protocol` | **New** | Shared collaboration schema; Swift speaks the same protocol. |

---

## 5. Capability → package coverage

The 15 baseline specs map onto the TS packages so coverage is auditable:

| OpenSpec capability | Primary TS package |
|---|---|
| data-model · file-format · editing-history | `@cyberdynecorp/excalidraw-model` |
| geometry-and-math | `@cyberdynecorp/excalidraw-math`, `@cyberdynecorp/excalidraw-geometry` |
| hand-drawn-rendering | `roughjs` + `perfect-freehand` (+ thin adapters in `@cyberdynecorp/excalidraw-render`) |
| scene-rendering | `@cyberdynecorp/excalidraw-render` (Canvas2D) |
| metal-rendering | `@cyberdynecorp/excalidraw-render-webgl` (deferred tier) |
| drawing-tools · selection-and-transform · arrows-and-bindings · smart-features · generators | `@cyberdynecorp/excalidraw-editor` |
| persistence | `@cyberdynecorp/excalidraw-model` (codecs) + `@cyberdynecorp/excalidraw-svelte` (File System Access API, autosave) |
| platform-ux | `@cyberdynecorp/excalidraw-svelte` + `apps/web` |
| collaboration | `@cyberdynecorp/excalidraw-protocol` + `server/` + clients (web `@cyberdynecorp/excalidraw-svelte`, Swift `ExcalidrawCollab`) |

---

## 6. Technology stack

- **Language:** TypeScript, `strict` + `noUncheckedIndexedAccess`.
- **Package manager / monorepo:** pnpm workspaces (+ Turborepo for task graph & caching).
- **Bundling:** `tsup`/`unbuild` for libraries; **Vite** for the app.
- **UI:** **Svelte 5 runes** (`$state`, `$derived`, `$effect`). The `EditorModel` equivalent is a runes class holding `$state` scene/viewport/selection and forwarding to `@cyberdynecorp/excalidraw-editor`.
- **Rendering:** Canvas2D first (`<canvas>` with devicePixelRatio scaling); rough.js renders directly to the 2D context.
- **Input:** Pointer Events API (covers mouse, touch, **Apple Pencil via `pointerType: "pen"` + `pressure`**), `gesturechange` / two-pointer pinch for pan/zoom, palm rejection by tracking the active pen pointer.
- **Testing:** **Vitest** (unit), **Playwright** (e2e + visual/golden screenshots).
- **Lint/format:** Biome (fast) — or ESLint + Prettier if preferred.
- **Versioning/release:** Changesets.
- **CI:** GitHub Actions, including the cross-language **conformance** job (§8).

---

## 7. Phased roadmap

Phases mirror the Swift [`docs/ROADMAP.md`](ROADMAP.md) so progress is comparable. Each phase has an **exit criterion**.

### T0 — Foundations
- pnpm workspace, Turborepo, TS strict, Vitest, Playwright, Biome, Changesets, CI skeleton.
- Port `@cyberdynecorp/excalidraw-math` (points, vectors, angles, numeric utils, ranges, curves/splines).
- Stand up the `fixtures/` directory + the conformance test harness (§8).
- **Exit:** `@cyberdynecorp/excalidraw-math` at parity with `ExcalidrawMathTests`; CI green; one shared fixture verified in both languages.

### T1 — Model & file format
- `@cyberdynecorp/excalidraw-model`: element types (all 13 kinds), scene + indexed access, AppState, `JSONValue`/`customData`, versioned `mutate`, soft-delete, fractional indexing, history (diff/undo/redo), `.excalidraw` v2 + `.excalidrawlib` codecs, lenient `restore`.
- **Exit:** byte-compatible round-trip with Swift on every fixture; `data-model` / `file-format` / `editing-history` specs satisfied.

### T2 — Geometry
- `@cyberdynecorp/excalidraw-geometry`: bounds, outline extraction, point-in-polygon, threshold hit-testing, ellipse/segment/rect/triangle intersections, viewport culling, dirty regions, frame containment, snapping + guides, **elbow-arrow routing (A\*)**, heading quantization, procedural shapes.
- Wire in `roughjs` + `perfect-freehand`.
- **Exit:** `geometry-and-math` + hand-drawn parity fixtures pass.

### T3 — Rendering (Canvas2D)
- `@cyberdynecorp/excalidraw-render`: viewport transform, theme/grid/background, element dispatch, op-set drawing, `ElementDrawable`, RoughOptions builder, text layout (with the same font-family mapping/fallbacks), image+crop, frames, interactive overlay, layered static/dynamic cache, PNG (incl. `tEXt` scene-embed) + SVG export.
- **Exit:** `scene-rendering` golden images match Swift within tolerance; PNG re-open round-trips across both clients.

### T4 — Editor engine
- `@cyberdynecorp/excalidraw-editor`: tool model + creation, selection/multi-select, move/resize/rotate, group/align/flip/z-order/lock/duplicate, copy/paste, linear point edit, image crop, arrow binding + elbow segment pinning, arrowheads, smart features (object/gap snap, freehand shape recognition + hold-to-snap, flowchart spawning, hyperlinks), generators (Mermaid, tables, charts, sticky notes).
- **Exit:** `drawing-tools`, `selection-and-transform`, `arrows-and-bindings`, `smart-features`, `generators` specs satisfied; ports of the Swift editor tests pass.

### T5 — Svelte 5 UI
- `@cyberdynecorp/excalidraw-svelte` + `apps/web`: runes store bridging `@cyberdynecorp/excalidraw-editor`; pointer/touch/pen input + palm rejection; two-pointer pan/zoom; adaptive layout; toolbar/properties/command palette (⌘K); keyboard shortcuts; color picker (`<input type=color>` / EyeDropper API); arrowhead picker; laser/eraser trails; zoom controls; dark mode; localization + RTL; documents (File System Access API + autosave to IndexedDB/localStorage + recents); web embeds (sandboxed `<iframe>` + host allow-list).
- **Exit:** `persistence` + `platform-ux` specs satisfied; Playwright e2e mirrors the Swift `SmokeUITests` flows.

### T6 — Parity hardening
- Cross-language golden-image suite, performance budget, accessibility pass, docs.
- **Exit:** visual diff vs Swift goldens within tolerance; perf acceptable on mid-range hardware.

### T7 — Phase 8: Collaboration (the goal) — ✅ delivered
- `@cyberdynecorp/excalidraw-protocol`, `server/` relay, presence/cursors, element sync + reconcile, reconnect; Swift client (`Sources/ExcalidrawCollab`) implements the same protocol. See §9.
- **Exit (met):** an iPad simulator and a browser edit the same room live — cursors, selections, and elements sync both ways; survives reconnects. Automated by `web/scripts/collab-live.sh`. (In-memory relay snapshot only; durable/Redis persistence deferred.)

---

## 8. Cross-client parity strategy

The risk in maintaining two libraries is **silent drift**. Mitigations:

1. **Shared golden fixtures** (`fixtures/`):
   - canonical `.excalidraw` scenes → expected canonical JSON (serialization parity),
   - rough.js op-sets at fixed seeds (render-geometry parity),
   - SVG export snapshots, PNG `tEXt` payloads,
   - golden PNG images (visual parity, with tolerance).
2. **Both test suites consume the same fixtures.** Swift `XCTest` and TS `Vitest` each assert against `fixtures/`. A diff fails CI in whichever language drifted.
3. **Specs as the merge point.** A behavior change is proposed once in `openspec/`, then implemented in both; the spec breadcrumbs point at both `Sources/…` and `web/packages/…`.
4. **Determinism guarantees.** The seeded RNG (LCG), fractional indexing, and version/nonce reconciliation are pinned by fixtures so JS↔Swift float/encoding differences are caught early.

---

## 9. Phase 8 — custom WebSocket protocol

**Transport:** raw WebSocket (no Socket.IO). JSON for v1 (debuggable); upgrade hot paths to MessagePack/binary later.

**Schema source of truth:** define `@cyberdynecorp/excalidraw-protocol` once and generate/mirror the Swift types. Options, in preference order: (a) **Protobuf** (`protoc` → TS + Swift) for a typed binary-ready contract; (b) a TS-first schema (Zod/TypeBox) with a Swift codegen step; (c) hand-maintained types validated by a shared JSON-Schema fixture. Recommend **(a) Protobuf**.

**Message types (sketch):**
| Message | Direction | Freq | Purpose |
|---|---|---|---|
| `join` / `leave` | client→server | once | enter/exit a room with identity (name, color, id) |
| `room-state` | server→client | on join | current peers + latest scene snapshot |
| `presence` | bidirectional | ~throttled | cursor position, selected ids, active tool, viewport |
| `pointer` | bidirectional | high, lossy | live cursor stream (may drop frames) |
| `element-updates` | bidirectional | on edit | versioned element deltas (id + full element or patch) |
| `scene-snapshot` | bidirectional | periodic | full-scene resync for late joiners / drift repair |
| `ack` / `ping` | bidirectional | heartbeat | liveness + reconnection |

**Reconciliation:** reuse the model's `version` / `versionNonce` / `updated` rule — on receiving an `element-updates`, keep the element with the higher `version` (tie-break on `versionNonce`). This is already implemented in `@cyberdynecorp/excalidraw-model` and the Swift `Scene.mutate`, so both clients converge identically. No separate CRDT needed for v1.

**Server (`server/`):** stateless Node relay (`ws` or `uWebSockets.js`) — room registry, broadcast fan-out, presence tracking, optional in-memory/Redis scene snapshot for late joiners. Horizontally scalable behind a sticky-room hash. **End-to-end encryption** (room key in the URL fragment, AES-GCM) is an *optional follow-up* layer once plaintext rooms work.

**Swift side:** `URLSessionWebSocketTask` client implementing the same `@cyberdynecorp/excalidraw-protocol` messages; the existing reconcile path consumes `element-updates` directly.

Each sub-capability (presence, element-sync, persistence/reconnect, encryption) becomes its **own OpenSpec change** at implementation time, adding a `collaboration` spec to the baseline.

---

## 10. Testing & CI

- **Unit:** Vitest per package, ports of the Swift unit tests.
- **Conformance:** the shared-fixtures job (§8) runs in both Swift and TS CI.
- **Visual:** Playwright screenshots vs Swift golden images (tolerance-bounded).
- **E2E:** Playwright flows mirroring `SmokeUITests`.
- **Collaboration (T7):** two headless browser contexts + a Swift simulator client against one relay; assert convergence.
- Coverage target ≥ 90% (match the Swift gate).

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Two libraries drift apart | Shared fixtures + specs-as-contract + cross-language CI (§8) |
| Canvas2D ≠ Core Graphics (text metrics, AA) | Tolerance-bounded golden diffs; ship the same font set; pin line-height/measure rules in fixtures |
| rough.js seed float differences JS↔Swift | Already validated; lock with op-set fixtures |
| Maintenance cost of a twin | Reuse `roughjs`/`perfect-freehand`; generate protocol types; keep core framework-agnostic |
| Svelte 5 runes churn / newness | Confine reactivity to `@cyberdynecorp/excalidraw-svelte`; keep `@cyberdynecorp/excalidraw-editor` pure and unit-tested without a DOM |
| Protocol lock-in | Version the protocol; `room-state` carries a protocol version; design for renegotiation |

---

## 12. Decisions (resolved)

1. **Repo layout** — ✅ polyglot monorepo here (`web/` workspace alongside `Sources/`, `openspec/`, `Fixtures/`).
2. **Protocol schema tooling** — ✅ JSON wire (v1) with a sorted-key **canonical** form locked by shared `Fixtures/protocol/*.json` fixtures (both clients hand-maintain matching types); Protobuf deferred.
3. **Reuse depth** — ✅ reuse `roughjs` + `perfect-freehand` (npm) in the web build.
4. **App framework** — ✅ Vite SPA (`apps/web`).
5. **E2E encryption** — ✅ plaintext rooms first; E2E encryption deferred as a follow-up.

---

## 13. Milestone sequence (rough)

```
T0 Foundations ─► T1 Model ─► T2 Geometry ─► T3 Render ─► T4 Editor ─► T5 Svelte UI ─► T6 Parity ─► T7 Collaboration
        math         codecs      hit/snap     Canvas2D    state mach.   runes app      goldens      custom WS
```

T1–T4 are the long pole (the framework-agnostic core) and are where shared fixtures pay off most. T5 is the first time it's *visible* in a browser. T7 delivers the cross-platform multiplayer goal.

> When implementation starts, each phase (or sub-capability) is tracked as a normal OpenSpec change against the baseline in [`openspec/specs/`](../openspec/specs/), so the Swift and TypeScript twins stay provably in sync.
