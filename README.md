# Excalidraw — Native Swift + TypeScript/Svelte port

Two from-scratch ports of [Excalidraw](https://excalidraw.com), built as **twins** that share one data model, the same `.excalidraw` v2 file format, a language-neutral [OpenSpec](openspec/) contract, and a custom WebSocket **collaboration protocol** — so they edit the same scene together:

- **Native iOS / iPadOS** in **Swift / SwiftUI** (`Sources/`, `App/`) — first-class Apple Pencil, finger-friendly UX, Core Graphics + an optional **Metal** GPU renderer.
- **Web** in **TypeScript + Svelte 5** (`web/` pnpm workspace) — Canvas2D, reusing the upstream `roughjs` / `perfect-freehand` the Swift side re-ported.

> **Status: both implementations feature-complete, and real-time iPad ↔ browser collaboration is delivered.** An iPad simulator and a browser join one room over a Node relay and converge live — verified end-to-end (XCUITest + Playwright). **599 Swift tests** (~92% logic coverage) · **409 web unit tests + 16 Playwright E2E** · CI green on both pipelines. Remaining work is a small set of tracked gaps — see **[Known gaps](#known-gaps)**.

---

## Features

Unless noted, features exist in **both** implementations (the editor engine, model, geometry, and rendering math are ported 1:1).

### Drawing & tools
Rectangle, diamond, ellipse, line, arrow (incl. **elbow / orthogonal** arrows with draggable fixed segments), freedraw (pressure), text, image, eraser, hand, frames, **sticky notes**, **tables**, **charts** (bar / line).

### Hand-drawn rendering
The rough.js look with numeric parity locked across languages: Swift `RoughKit` (a rough.js re-port) and the web's upstream `roughjs` produce **byte-identical op-sets** at fixed seeds. All fill styles (hachure / cross-hatch / solid / zigzag), **sloppiness** (architect / artist / cartoonist), sharp/round edges, splined multi-point lines, rounded rectangles, and arrowheads.

### Editing
Select / multi-select, group-aware selection, move / resize / rotate (**font scales on resize**), undo/redo, copy/paste, z-order, align, flip, group/ungroup, lock, duplicate, on-canvas text editing, and **linear point ("spline") editing** (double-click a line/arrow to drag vertices and split midpoints).

### Smart features
Object + gap **snapping** with guides, arrow↔shape **binding** (re-routes on move/resize), **freehand shape recognition** ("Snap to Shape": rectangle / ellipse / diamond / triangle / line / pentagon / hexagon / star / heart / cloud / speech-bubble, hold-to-snap), **flowchart** node spawning, interactive **image crop**, and element **hyperlinks**.

### Generators & embeds
**Mermaid → diagram** (paste a flowchart), **tables** (with add-row / add-column), **charts** (double-click to change plot type + data), **sticky notes**, flowchart nodes. The Swift app also renders **live web embeddables** (`WKWebView` behind a host allow-list).

### Real-time collaboration (iPad ↔ browser)
A custom WebSocket protocol (`@cyberdynecorp/excalidraw-protocol` / Swift `ExcalidrawCollab`) spoken **byte-identically** by both clients and locked by a shared `Fixtures/protocol/` corpus. A Node relay (`web/server/`) handles rooms, presence, and a scene snapshot for late joiners. Concurrent edits resolve with the model's deterministic, symmetric **`version` / `versionNonce`** last-writer-wins reconciliation — identical on both sides, no central authority or CRDT. Live **peer cursors / selection / tool** presence, per-peer id namespacing, and **auto-reconnect** that resyncs without losing offline edits.

### Files & export
`.excalidraw` / `.excalidrawlib` round-trip with excalidraw.com (canonical, sorted-key JSON — byte-compatible across both languages); **SVG** export; **PNG** export with **`tEXt` scene-embed round-trip** (re-open a drawing from its exported PNG). The Swift app adds Files-app open/save + **autosave + recents** and an on-disk library.

### Platform polish
- **Swift app:** size-class-adaptive iPhone/iPad UI, dark mode, zen mode, command palette, hardware-keyboard shortcuts, two-finger pan/zoom, palm rejection, **Apple Pencil hover (17.5+) & Pencil Pro squeeze**, **laser pointer** + animated eraser trail, arrowhead-type picker, custom color picker (+ system eyedropper), localization (en/es/ar incl. RTL).
- **Web app:** full toolbar / properties / generators, pointer + wheel pan/zoom, on-canvas text editing, fill-pattern selector, laser/eraser trails, zoom + theme toggle, SVG/`.excalidraw` export, and the live-collaboration UI (peer roster + remote cursors).

### Rendering backends
- **Swift:** Core Graphics (default) + an optional **Metal GPU renderer** (`ExcalidrawMetal`), runtime-switchable with automatic CG fallback; layered static/dynamic split + gesture snapshots; an in-app CPU-vs-GPU benchmark. See [Phase 7.5](docs/ROADMAP.md#phase-75--rendering-acceleration--performance).
- **Web:** Canvas2D (`@cyberdynecorp/excalidraw-render`) with `roughjs` + `perfect-freehand`; SVG export and PNG scene-embed.

---

## Two implementations, one contract

The risk in maintaining twins is silent drift. Mitigations, enforced in CI:

- **OpenSpec is the contract.** Both implementations are built against the [`openspec/specs/`](openspec/specs/) baseline (15 capabilities). A behavior change goes through OpenSpec once and lands in both.
- **Shared golden fixtures** in [`Fixtures/`](Fixtures/): `.excalidraw` scenes (serialization parity), rough.js op-sets at fixed seeds (render-geometry parity), canonical-JSON / SVG goldens, and `protocol/*.json` wire frames — each asserted by **both** the Swift `XCTest` and the TypeScript `Vitest` suites.
- **Reuse where parity is free.** The web build uses the original `roughjs` / `perfect-freehand` npm packages; the Swift side re-ported them and validated numeric parity against the same references.

<a name="known-gaps"></a>
## Known gaps (deferred)
In sync with the code; full detail in [docs/ROADMAP.md](docs/ROADMAP.md#known-gaps--deferred-items).
- **Collaboration tail** — relay scene persistence is **in-memory** (durable / Redis deferred); **end-to-end encryption** and **follow mode** deferred.
- **Fidelity** — the **bundled Excalidraw font files** aren't committed (loading + family mapping is wired, so dropping the `.ttf/.otf` in takes effect; until then text uses system fallbacks). Hachure fill and perfect-freehand outlines are visually faithful, not line-identical. Canvas2D vs Core Graphics rendering is tolerance-bounded, not pixel-identical (the hand-drawn geometry that produces it is byte-identical).
- **Web rendering tiers** — a `@cyberdynecorp/excalidraw-render-webgl` GPU tier is deferred (Canvas2D ships); a headless PNG **rasterizer** is deferred (PNG scene-embed metadata round-trips today).
- **Swift documents** — Files-app open/save + autosave + recents rather than a full `DocumentGroup` browser-on-launch.

---

## Repository layout

```
excalidraw-swift-web/
├── Sources/            Swift packages (the iOS/iPad implementation)
│   ├── ExcalidrawMath · ExcalidrawModel · ExcalidrawGeometry
│   ├── RoughKit · FreehandKit · ExcalidrawRender · ExcalidrawMetal
│   ├── ExcalidrawEditor · ExcalidrawCollab · ExcalidrawUI
├── App/                the SwiftUI app shell (ExcalidrawApp)
├── web/                TypeScript + Svelte 5 twin (pnpm workspace)
│   ├── packages/       @cyberdynecorp/excalidraw-math · model · geometry · render · editor · svelte · protocol
│   ├── apps/web/       the browser app (Vite + Svelte 5)
│   └── server/         @cyberdynecorp/excalidraw-relay — Node WebSocket relay
├── openspec/specs/     language-neutral baseline specs (the shared contract)
├── Fixtures/           shared golden fixtures (scenes, rough seeds, protocol wire)
└── docs/               investigation, plan, roadmaps
```

### Swift architecture
Layered, framework-light core (pure Swift, simulator-independent) under a thin SwiftUI shell:

`ExcalidrawMath` → `ExcalidrawModel` → `ExcalidrawGeometry` · `RoughKit` · `FreehandKit` → `ExcalidrawRender` → `ExcalidrawMetal` · `ExcalidrawEditor` · `ExcalidrawCollab` → `ExcalidrawUI` → `ExcalidrawApp`

(`ExcalidrawEditor` is the pure, UIKit-free editor state machine; `ExcalidrawCollab` is the collaboration client + protocol; `ExcalidrawMetal` is the optional GPU renderer behind the same `SceneRendering` protocol as the Core Graphics `SceneRenderer`. All bridged to SwiftUI by `ExcalidrawUI`'s `EditorModel`.)

### Web architecture
A pure TS core under a thin Svelte 5 runes layer, mirroring the Swift split: `@cyberdynecorp/excalidraw-editor` (pure state machine) under `@cyberdynecorp/excalidraw-svelte` (`EditorStore` runes bridge), with `@cyberdynecorp/excalidraw-render` (Canvas2D), `@cyberdynecorp/excalidraw-protocol` (collaboration), and the `@cyberdynecorp/excalidraw-relay` relay.

---

## Using as a dependency

Both implementations are packaged for reuse in other projects.

- **Web (GitHub Packages, scope `@cyberdynecorp`, ESM):** point the scope at GitHub Packages in `.npmrc`, then install the layers you need.

  ```ini
  # .npmrc
  @cyberdynecorp:registry=https://npm.pkg.github.com
  //npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
  ```
  ```sh
  npm install @cyberdynecorp/excalidraw-model @cyberdynecorp/excalidraw-editor    # headless engine
  npm install @cyberdynecorp/excalidraw-svelte                          # reactive store (pulls the rest)
  npm install @cyberdynecorp/excalidraw-protocol @cyberdynecorp/excalidraw-relay  # collaboration
  ```
  Packages: `math · model · geometry · render · editor · svelte · protocol · server`. See [web/README.md](web/README.md#install-github-packages) for usage + the maintainer publish flow.

- **Swift (SwiftPM):** add the package and depend on the products you need.

  ```swift
  .package(url: "https://github.com/leonardoaraujosantos/excalidraw-swift-web.git", from: "0.1.0")
  // products: ExcalidrawModel, ExcalidrawGeometry, ExcalidrawEditor,
  //           ExcalidrawCollab, ExcalidrawRender, ExcalidrawUI, RoughKit, FreehandKit, …
  ```

## Building & running

### iOS / iPadOS (Swift)
Open **`ExcalidrawSwift.xcodeproj`** and run the `ExcalidrawApp` scheme. The libraries also build/test without Xcode via `swift build` / `swift test`. The project is generated from `project.yml` via [XcodeGen](https://github.com/yonsm/XcodeGen) but committed for stability; regenerate after changing `Package.swift` / `project.yml`:

```sh
brew install xcodegen        # once
./scripts/generate.sh        # regenerate + clear stale caches
```

### Web (TypeScript + Svelte 5)
Requires Node ≥ 20.19 and pnpm 10.

```sh
cd web
pnpm install
pnpm test          # vitest across all packages
pnpm typecheck     # tsc --noEmit per package
pnpm lint          # biome
pnpm --filter excalidraw-web-app dev          # run the app
pnpm --filter excalidraw-web-app e2e          # Playwright end-to-end
```

### Live cross-platform collaboration (macOS + Xcode)
Starts a relay, joins a browser (Playwright) and the real SwiftUI app in an iOS simulator to one room, and asserts both converge:

```sh
web/scripts/collab-live.sh   # requires xcodegen
```

---

## Documents
- **[docs/INVESTIGATION.md](docs/INVESTIGATION.md)** — analysis of the upstream source: data model, file format, rendering, interaction, geometry/math, full feature inventory.
- **[docs/PLAN.md](docs/PLAN.md)** — Swift architecture, package structure, design decisions, testing strategy, risks.
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — phased Swift delivery plan (Phase 0 → Phase 8 collaboration) with per-phase status + **[Known gaps & deferred items](docs/ROADMAP.md#known-gaps--deferred-items)**.
- **[docs/TYPESCRIPT_SVELTE_PORT.md](docs/TYPESCRIPT_SVELTE_PORT.md)** — the TypeScript + Svelte 5 twin roadmap (T0 → T7), delivered.
- **[web/README.md](web/README.md)** — the web workspace: packages, status, and how to develop/test.
- **[openspec/](openspec/)** — language-neutral OpenSpec baseline specs (15 capabilities, incl. `collaboration`) both implementations are built against.
