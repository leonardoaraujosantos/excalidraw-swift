import {
  EditorController,
  type FlowchartDirection,
  type PointerPhase,
  type PointerType,
  type Tool,
  pointerEvent,
} from "../editor/index.js";
import { Point } from "../math/index.js";
import {
  type ExcalidrawElement,
  type FillStyle,
  RoundnessType,
  Scene,
  SceneDocument,
  type StrokeStyle,
} from "../model/index.js";
import type { Peer } from "../protocol/index.js";
import { reconcileElements } from "../protocol/index.js";
import {
  type RenderContext,
  type Theme,
  Viewport,
  ZOOM_RANGE,
  renderOverlay as drawOverlay,
  exportSvg,
  renderScene,
} from "../render/index.js";
import { CollabSession, type CollabSocket, type RemoteCursor } from "./collab-session.js";
import { TrailStore } from "./trail-store.js";

function nowSeconds(): number {
  return (typeof performance !== "undefined" ? performance.now() : 0) / 1000;
}

function clampZoom(zoom: number): number {
  return Math.min(Math.max(zoom, ZOOM_RANGE.min), ZOOM_RANGE.max);
}

export interface PointerOptions {
  type?: PointerType;
  pressure?: number;
  shift?: boolean;
  alt?: boolean;
  toggle?: boolean;
  /** Current time (seconds) for laser/eraser trails; defaults to `performance.now()`. */
  now?: number;
}

/**
 * Bridges the pure `EditorController` to a UI: forwards pointer events
 * (converting view → scene coordinates), owns the viewport, and bumps a
 * `revision` counter so the canvas redraws after each change. Plain TS so it is
 * unit-testable; a Svelte component wraps it in `$state`. (parity: EditorModel.swift)
 */
export class EditorStore {
  readonly controller: EditorController;
  readonly trail = new TrailStore();
  viewport: Viewport;
  revision = 0;
  theme: Theme = "light";
  zenMode = false;
  /** On-canvas text editing state (`null` when not editing). `viewW`/`viewH` size
   * the editor to a container (cell/sticky note); absent for free text. */
  editingText: {
    id: string;
    value: string;
    viewX: number;
    viewY: number;
    viewW?: number;
    viewH?: number;
  } | null = null;
  /** Chart editing state (`null` when not editing): plot kind + CSV data. */
  editingChart: {
    group: string;
    kind: "bar" | "line";
    values: string;
    viewX: number;
    viewY: number;
  } | null = null;
  /** Last known canvas size, for zoom-to-fit and generator placement. */
  canvasWidth = 1024;
  canvasHeight = 768;
  /** Active collaboration session (`null` when editing solo). */
  collab: CollabSession | null = null;
  /** Per-element version last broadcast, to send only what changed (and avoid echo). */
  private lastBroadcast = new Map<string, number>();
  /** Listeners notified after each local edit — used by external collaboration
   * adapters (e.g. the optional Yjs/CRDT adapter) to mirror edits to a `Y.Doc`. */
  private changeListeners = new Set<() => void>();
  /** Listeners notified of local cursor moves (scene coords) — external presence
   * adapters publish these as their own cursor. */
  private cursorListeners = new Set<(scene: Point) => void>();
  /** Remote cursors supplied by an external presence source (e.g. the Yjs
   * awareness bridge); merged with the LWW `remoteCursors` when rendering. */
  externalCursors: { color: string; name: string; x: number; y: number }[] = [];

  constructor(scene: Scene = new Scene(), viewport: Viewport = new Viewport()) {
    this.controller = new EditorController(scene);
    this.controller.zoom = viewport.zoom;
    this.viewport = viewport;
  }

  private bump(): void {
    this.revision += 1;
    this.broadcastLocalChanges();
    for (const listener of this.changeListeners) listener();
  }

  get scene(): Scene {
    return this.controller.scene;
  }
  get activeTool(): Tool {
    return this.controller.activeTool;
  }
  get canUndo(): boolean {
    return this.controller.canUndo;
  }
  get canRedo(): boolean {
    return this.controller.canRedo;
  }
  get zoomPercent(): number {
    return Math.round(this.viewport.zoom * 100);
  }

  /** A short stats string for the current selection (size in points). */
  get selectionStats(): string | null {
    const b = this.controller.selectionBounds;
    if (b === null) return null;
    return `${Math.round(b.width)} × ${Math.round(b.height)}`;
  }

  // MARK: Pointer input (view coordinates in)

  pointer(phase: PointerPhase, viewPoint: Point, opts: PointerOptions = {}): void {
    // The text tool taps to place an on-canvas editor instead of dragging.
    if (this.activeTool === "text" && phase === "down") {
      this.beginText(viewPoint);
      return;
    }
    const scenePoint = this.viewport.viewToScene(viewPoint);
    const now = opts.now ?? nowSeconds();

    // The laser pointer only paints a fading trail — it creates/selects nothing.
    if (this.activeTool === "laser") {
      if (phase !== "up") this.trail.addLaser(scenePoint, now);
      this.bump();
      return;
    }
    // The eraser paints a trail AND still erases (forwarded below).
    if (this.activeTool === "eraser" && phase !== "up") {
      this.trail.addEraser(scenePoint, now);
    }

    const event = pointerEvent(scenePoint, phase, {
      type: opts.type,
      pressure: opts.pressure,
      shift: opts.shift,
      alt: opts.alt,
      toggleSelection: opts.toggle,
    });
    if (phase === "down") this.controller.pointerDown(event);
    else if (phase === "move") this.controller.pointerMove(event);
    else this.controller.pointerUp(event);
    this.bump();

    if (this.collab !== null) {
      this.collab.sendPointer({ x: scenePoint.x, y: scenePoint.y });
      if (phase === "up") {
        this.collab.sendPresence({
          pointer: { x: scenePoint.x, y: scenePoint.y },
          selectedIds: [...this.controller.selectedIDs],
          tool: this.activeTool,
        });
      }
    }
  }

  /** Broadcast the cursor without a click — for hover/move tracking from the UI.
   * Notifies both the LWW session and any external presence adapter. */
  trackPointer(viewPoint: Point): void {
    const p = this.viewport.viewToScene(viewPoint);
    for (const listener of this.cursorListeners) listener(p);
    if (this.collab !== null) this.collab.sendPointer({ x: p.x, y: p.y });
  }

  // MARK: Viewport

  panZoom(translationX: number, translationY: number, scale = 1): void {
    const v = this.viewport;
    v.zoom = clampZoom(v.zoom * scale);
    v.scrollX += translationX / v.zoom;
    v.scrollY += translationY / v.zoom;
    this.controller.zoom = v.zoom;
    this.bump();
  }

  zoomTo(zoom: number): void {
    this.viewport.zoom = clampZoom(zoom);
    this.controller.zoom = this.viewport.zoom;
    this.bump();
  }
  zoomIn(): void {
    this.zoomTo(this.viewport.zoom * 1.2);
  }
  zoomOut(): void {
    this.zoomTo(this.viewport.zoom / 1.2);
  }
  resetZoom(): void {
    this.zoomTo(1);
  }

  // MARK: Tool + style commands

  selectTool(tool: Tool): void {
    this.controller.setTool(tool);
    this.bump();
  }

  private applyToSelection(change: (el: ExcalidrawElement) => void): void {
    this.controller.updateSelected(change);
    this.bump();
  }

  setStrokeColor(color: string): void {
    this.controller.currentItem.strokeColor = color;
    this.applyToSelection((el) => {
      el.strokeColor = color;
    });
  }
  setStrokeWidth(width: number): void {
    this.controller.currentItem.strokeWidth = width;
    this.applyToSelection((el) => {
      el.strokeWidth = width;
    });
  }
  setBackgroundColor(color: string): void {
    this.controller.currentItem.backgroundColor = color;
    this.applyToSelection((el) => {
      el.backgroundColor = color;
    });
  }
  setFillStyle(style: FillStyle): void {
    this.controller.currentItem.fillStyle = style;
    this.applyToSelection((el) => {
      el.fillStyle = style;
    });
  }
  setStrokeStyle(style: StrokeStyle): void {
    this.controller.currentItem.strokeStyle = style;
    this.applyToSelection((el) => {
      el.strokeStyle = style;
    });
  }
  setOpacity(opacity: number): void {
    this.controller.currentItem.opacity = opacity;
    this.applyToSelection((el) => {
      el.opacity = opacity;
    });
  }
  setRoughness(roughness: number): void {
    this.controller.currentItem.roughness = roughness;
    this.applyToSelection((el) => {
      el.roughness = roughness;
    });
  }
  setRoundEdges(round: boolean): void {
    this.controller.currentItem.roundEdges = round;
    this.applyToSelection((el) => {
      el.roundness = round ? { type: RoundnessType.adaptiveRadius } : null;
    });
  }
  setElbowed(elbowed: boolean): void {
    this.controller.setElbowed(elbowed);
    this.bump();
  }
  toggleSnap(): void {
    this.controller.snapEnabled = !this.controller.snapEnabled;
    this.bump();
  }

  // MARK: Edit + history

  undo(): void {
    this.controller.undo();
    this.bump();
  }
  redo(): void {
    this.controller.redo();
    this.bump();
  }
  deleteSelected(): void {
    this.controller.deleteSelected();
    this.bump();
  }
  duplicate(): void {
    this.controller.duplicate();
    this.bump();
  }
  group(): void {
    this.controller.group();
    this.bump();
  }
  ungroup(): void {
    this.controller.ungroup();
    this.bump();
  }
  selectAll(): void {
    this.controller.selectAll();
    this.bump();
  }
  align(alignment: Parameters<EditorController["align"]>[0]): void {
    this.controller.align(alignment);
    this.bump();
  }
  flip(horizontal: boolean): void {
    this.controller.flip(horizontal);
    this.bump();
  }
  setLocked(locked: boolean): void {
    this.controller.setLocked(locked);
    this.bump();
  }
  reorder(order: Parameters<EditorController["reorder"]>[0]): void {
    this.controller.reorder(order);
    this.bump();
  }

  /** Insert an image (downscaled to a max dimension) at the viewport centre. */
  insertImage(
    dataURL: string,
    mimeType: string,
    naturalWidth: number,
    naturalHeight: number,
  ): void {
    const scale = Math.min(1, 320 / Math.max(naturalWidth, naturalHeight, 1));
    const w = naturalWidth * scale;
    const h = naturalHeight * scale;
    const c = this.viewportCenterScene();
    this.controller.insertImage(dataURL, mimeType, new Point(c.x - w / 2, c.y - h / 2), w, h);
    this.bump();
  }

  // MARK: Generators (placed at the viewport centre)

  private viewportCenterScene(): Point {
    return this.viewport.viewToScene(new Point(this.canvasWidth / 2, this.canvasHeight / 2));
  }
  insertStickyNote(): void {
    const { container, text } = this.controller.createStickyNote(this.viewportCenterScene());
    this.beginBoundTextEdit(container, text);
    this.bump();
  }
  insertTable(rows = 3, cols = 3): void {
    this.controller.createTable(this.viewportCenterScene(), rows, cols);
    this.bump();
  }

  /** The table group id of the current selection, if it is (part of) a table. */
  get selectedTableGroup(): string | null {
    for (const id of this.controller.selectedIDs) {
      const group = this.controller.tableGroupID(id);
      if (group !== null) return group;
    }
    return null;
  }

  /** Append a row to the selected table (no-op if no table is selected). */
  addTableRow(): void {
    const group = this.selectedTableGroup;
    if (group === null) return;
    this.controller.addTableRow(group);
    this.reselectTable(group);
    this.bump();
  }

  /** Append a column to the selected table (no-op if no table is selected). */
  addTableColumn(): void {
    const group = this.selectedTableGroup;
    if (group === null) return;
    this.controller.addTableColumn(group);
    this.reselectTable(group);
    this.bump();
  }

  /** Re-select the whole table group so the selection grows with new cells. */
  private reselectTable(group: string): void {
    const ids = this.scene.visibleElements
      .filter((el) => this.controller.tableGroupID(el.id) === group)
      .map((el) => el.id);
    this.controller.selectedIDs = new Set(ids);
  }
  insertChart(values: number[], kind: "bar" | "line" = "bar"): void {
    this.controller.createChart(this.viewportCenterScene(), values, [], kind);
    this.bump();
  }
  insertMermaid(text: string): boolean {
    const ok = this.controller.insertMermaid(text, this.viewportCenterScene());
    this.bump();
    return ok;
  }
  addFlowchartNode(direction: FlowchartDirection): void {
    const id = [...this.controller.selectedIDs][0];
    if (id !== undefined) this.controller.addFlowchartNode(id, direction);
    this.bump();
  }
  recognizeSelectedStroke(): void {
    const id = [...this.controller.selectedIDs][0];
    if (id !== undefined) this.controller.recognizeFreedraw(id);
    this.bump();
  }

  // MARK: On-canvas text editing

  beginText(viewPoint: Point): void {
    const id = this.controller.createText(this.viewport.viewToScene(viewPoint));
    this.editingText = { id, value: "", viewX: viewPoint.x, viewY: viewPoint.y };
    this.bump();
  }

  /**
   * Begin editing the text bound to a container (e.g. a sticky note), placing
   * the on-canvas editor over the container. Used after inserting a sticky note
   * and when double-clicking an existing one.
   */
  private beginBoundTextEdit(containerId: string, textId: string): void {
    const container = this.scene.element(containerId);
    const text = this.scene.element(textId);
    if (container === undefined || text === undefined || text.type !== "text") return;
    const tl = this.viewport.sceneToView(new Point(container.x, container.y));
    const br = this.viewport.sceneToView(
      new Point(container.x + container.width, container.y + container.height),
    );
    // Size the editor to the container so a table cell / note label doesn't
    // overflow to the right of its box.
    this.editingText = {
      id: textId,
      value: text.text,
      viewX: tl.x,
      viewY: tl.y,
      viewW: br.x - tl.x,
      viewH: br.y - tl.y,
    };
  }

  /**
   * If a container with bound text is hit at `viewPoint` (a double-click),
   * begin editing its label. Returns whether editing started.
   */
  editBoundTextAt(viewPoint: Point): boolean {
    const hit = this.controller.boundTextHit(this.viewport.viewToScene(viewPoint));
    if (hit === null) return false;
    this.beginBoundTextEdit(hit.container, hit.text);
    this.bump();
    return true;
  }

  /**
   * Double-click handler: edit a sticky-note label if one is hit, otherwise
   * enter linear point ("spline") editing on a hit line/arrow so its vertices
   * can be dragged and midpoints split.
   */
  doubleClickAt(viewPoint: Point): void {
    if (this.editBoundTextAt(viewPoint)) return;
    const scenePoint = this.viewport.viewToScene(viewPoint);
    const chartGroup = this.controller.chartGroupAt(scenePoint);
    if (chartGroup !== null) {
      this.beginChartEdit(chartGroup, viewPoint);
      return;
    }
    if (this.controller.beginLinearEdit(scenePoint)) this.bump();
  }

  /** Whether a line/arrow is currently in point-editing mode (for the UI). */
  get isLinearEditing(): boolean {
    return this.controller.editingLinearID !== null;
  }

  // MARK: Chart editing (double-click a chart to change plot type + data)

  private beginChartEdit(group: string, viewPoint: Point): void {
    const info = this.controller.chartInfo(group);
    if (info === null) return;
    this.editingChart = {
      group,
      kind: info.kind,
      values: info.values.join(", "),
      viewX: viewPoint.x,
      viewY: viewPoint.y,
    };
    this.bump();
  }

  setChartKind(kind: "bar" | "line"): void {
    if (this.editingChart !== null) this.editingChart = { ...this.editingChart, kind };
  }
  setChartValues(values: string): void {
    if (this.editingChart !== null) this.editingChart = { ...this.editingChart, values };
  }

  /** Apply the edited plot type + data, rebuilding the chart in place. */
  commitChart(): void {
    if (this.editingChart === null) return;
    const values = this.editingChart.values
      .split(",")
      .map((s) => Number.parseFloat(s.trim()))
      .filter((v) => Number.isFinite(v));
    if (values.length > 0) {
      this.controller.updateChart(this.editingChart.group, this.editingChart.kind, values);
    }
    this.editingChart = null;
    this.bump();
  }

  cancelChart(): void {
    this.editingChart = null;
    this.bump();
  }

  // MARK: Collaboration

  /**
   * Join a collaboration room over `socket`. Local edits broadcast as
   * `element-updates`; remote edits are reconciled into the scene by
   * `version`/`versionNonce`. Returns the session.
   */
  startCollab(socket: CollabSocket, peer: Peer, room: string): CollabSession {
    // Namespace this client's generated ids so two peers never collide.
    this.controller.idPrefix = `${peer.id}-`;
    const session = new CollabSession(socket, peer, room, {
      onScene: (elements) => this.applyRemoteScene(elements),
      onRemoteElements: (elements) => this.applyRemoteElements(elements),
      onPresence: () => this.bump(),
    });
    this.collab = session;
    this.syncBroadcastBaseline();
    return session;
  }

  /** Stop collaborating (leaves the room and closes the socket). */
  stopCollab(): void {
    this.collab?.leave();
    this.collab = null;
  }

  /**
   * Subscribe to local edits — invoked after every mutation that bumps
   * `revision`. Returns an unsubscribe function. External collaboration adapters
   * (e.g. `@cyberdynecorp/excalidraw-yjs`) use this to mirror local edits into a
   * `Y.Doc`. Applying external elements via {@link applyExternalElements} does
   * **not** fire these listeners, so an adapter won't echo its own writes.
   */
  onChange(listener: () => void): () => void {
    this.changeListeners.add(listener);
    return () => this.changeListeners.delete(listener);
  }

  /**
   * Subscribe to local cursor moves (scene coordinates), fired from
   * {@link trackPointer}. External presence adapters publish these as the local
   * peer's cursor. Returns an unsubscribe function.
   */
  onCursorMove(listener: (scene: Point) => void): () => void {
    this.cursorListeners.add(listener);
    return () => this.cursorListeners.delete(listener);
  }

  /**
   * Replace the scene with elements merged by an external engine (e.g. a CRDT
   * adapter), without creating an undo step, without broadcasting on the LWW
   * collab transport, and without firing {@link onChange} (so it doesn't echo
   * back to the source). Bumps `revision` so the canvas redraws.
   */
  applyExternalElements(elements: ExcalidrawElement[]): void {
    this.controller.store.modifyScene((scene) => scene.replaceAll(elements));
    this.controller.store.rebase();
    this.revision += 1;
  }

  /** Remote peers' live cursors/selection, for presence rendering. */
  get remoteCursors(): RemoteCursor[] {
    return this.collab === null ? [] : [...this.collab.cursors.values()];
  }

  /**
   * Apply a room snapshot (on join / reconnect). The snapshot is *merged* with
   * the local scene by reconciliation rather than blindly replacing it, so edits
   * made while briefly disconnected survive — and anything the room doesn't yet
   * have (or that is locally newer) is re-broadcast after merging.
   */
  private applyRemoteScene(elements: ExcalidrawElement[]): void {
    const merged = reconcileElements(this.scene.elements, elements);
    this.controller.store.modifyScene((scene) => scene.replaceAll(merged));
    this.controller.store.rebase();
    // Treat only the room's versions as already-broadcast; local-only or
    // locally-newer elements stay "dirty" so broadcastLocalChanges re-publishes them.
    this.lastBroadcast.clear();
    for (const el of elements) this.lastBroadcast.set(el.id, el.version);
    this.revision += 1;
    this.broadcastLocalChanges();
  }

  /** Merge a versioned remote batch into the scene (reconciled, no undo step). */
  private applyRemoteElements(elements: ExcalidrawElement[]): void {
    const merged = reconcileElements(this.scene.elements, elements);
    this.controller.store.modifyScene((scene) => scene.replaceAll(merged));
    this.controller.store.rebase();
    this.syncBroadcastBaseline();
    this.revision += 1;
  }

  /** Mark every current element as already broadcast (call after applying remote). */
  private syncBroadcastBaseline(): void {
    this.lastBroadcast.clear();
    for (const el of this.scene.elements) this.lastBroadcast.set(el.id, el.version);
  }

  /** Send elements whose version changed since the last broadcast. */
  private broadcastLocalChanges(): void {
    if (this.collab === null) return;
    const changed: ExcalidrawElement[] = [];
    for (const el of this.scene.elements) {
      if (this.lastBroadcast.get(el.id) !== el.version) {
        changed.push(el);
        this.lastBroadcast.set(el.id, el.version);
      }
    }
    this.collab.broadcastElements(changed);
  }

  setEditingText(value: string): void {
    if (this.editingText !== null) this.editingText = { ...this.editingText, value };
  }

  commitText(): void {
    if (this.editingText === null) return;
    this.controller.setText(this.editingText.id, this.editingText.value);
    this.editingText = null;
    this.controller.setTool("selection");
    this.bump();
  }

  // MARK: Theme / zen

  setTheme(theme: Theme): void {
    this.theme = theme;
    this.bump();
  }
  toggleTheme(): void {
    this.setTheme(this.theme === "light" ? "dark" : "light");
  }
  toggleZen(): void {
    this.zenMode = !this.zenMode;
    this.bump();
  }

  // MARK: Render + documents

  render(
    ctx: RenderContext,
    width: number,
    height: number,
    images?: (fileId: string) => CanvasImageSource | null,
  ): void {
    this.canvasWidth = width;
    this.canvasHeight = height;
    renderScene(ctx, this.scene, {
      viewport: this.viewport,
      width,
      height,
      theme: this.theme,
      images,
    });
  }

  /** Draw the interactive overlay (selection, handles, marquee, edit handles, trails). */
  renderOverlay(ctx: RenderContext, width: number, height: number, now = nowSeconds()): void {
    const c = this.controller;
    const handlesMap = c.transformHandles();
    const rotationHandle = handlesMap.get("rotation") ?? null;
    const handles = [...handlesMap].filter(([k]) => k !== "rotation").map(([, p]) => p);

    let linearPoints: Point[] = [];
    let linearMidpoints: Point[] = [];
    if (c.editingLinearID !== null) {
      const el = c.scene.element(c.editingLinearID);
      if (el?.type === "arrow" && el.elbowed) {
        linearMidpoints = c.elbowSegmentHandles(c.editingLinearID).map((h) => h.point);
      } else {
        const h = c.linearEditHandles();
        if (h !== null) {
          linearPoints = h.points;
          linearMidpoints = h.midpoints;
        }
      }
    }

    drawOverlay(ctx, {
      viewport: this.viewport,
      width,
      height,
      selectionBounds: c.selectionBounds,
      handles,
      rotationHandle,
      selectionRect: c.selectionRect,
      snapLinesX: c.snapLinesX,
      snapLinesY: c.snapLinesY,
      linearPoints,
      linearMidpoints,
      cropFrame: c.cropFrame(),
      cropHandles: c.cropEditHandles() ?? [],
      now,
      laserDots: this.trail.visibleLaser(now),
      eraserDots: this.trail.visibleEraser(now),
      remoteCursors: [
        ...this.remoteCursors
          .filter((rc) => rc.pointer !== null)
          .map((rc) => ({
            color: rc.peer.color,
            name: rc.peer.name,
            x: rc.pointer!.x,
            y: rc.pointer!.y,
          })),
        ...this.externalCursors,
      ],
    });
  }

  exportSvg(): string {
    return exportSvg(this.scene);
  }

  documentJSON(): string {
    return SceneDocument.encode(this.scene);
  }

  loadDocument(json: string): void {
    this.controller.load(SceneDocument.decode(json));
    this.bump();
  }
}
