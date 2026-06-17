import {
  EditorController,
  type FlowchartDirection,
  type PointerPhase,
  type PointerType,
  type Tool,
  pointerEvent,
} from "@xs/editor";
import { Point } from "@xs/math";
import {
  type ExcalidrawElement,
  type FillStyle,
  RoundnessType,
  Scene,
  SceneDocument,
  type StrokeStyle,
} from "@xs/model";
import {
  type RenderContext,
  type Theme,
  Viewport,
  ZOOM_RANGE,
  exportSvg,
  renderScene,
} from "@xs/render";

function clampZoom(zoom: number): number {
  return Math.min(Math.max(zoom, ZOOM_RANGE.min), ZOOM_RANGE.max);
}

export interface PointerOptions {
  type?: PointerType;
  pressure?: number;
  shift?: boolean;
  alt?: boolean;
  toggle?: boolean;
}

/**
 * Bridges the pure `EditorController` to a UI: forwards pointer events
 * (converting view → scene coordinates), owns the viewport, and bumps a
 * `revision` counter so the canvas redraws after each change. Plain TS so it is
 * unit-testable; a Svelte component wraps it in `$state`. (parity: EditorModel.swift)
 */
export class EditorStore {
  readonly controller: EditorController;
  viewport: Viewport;
  revision = 0;
  theme: Theme = "light";
  zenMode = false;
  /** Last known canvas size, for zoom-to-fit and generator placement. */
  canvasWidth = 1024;
  canvasHeight = 768;

  constructor(scene: Scene = new Scene(), viewport: Viewport = new Viewport()) {
    this.controller = new EditorController(scene);
    this.controller.zoom = viewport.zoom;
    this.viewport = viewport;
  }

  private bump(): void {
    this.revision += 1;
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
    const scenePoint = this.viewport.viewToScene(viewPoint);
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

  // MARK: Generators (placed at the viewport centre)

  private viewportCenterScene(): Point {
    return this.viewport.viewToScene(new Point(this.canvasWidth / 2, this.canvasHeight / 2));
  }
  insertStickyNote(): void {
    this.controller.createStickyNote(this.viewportCenterScene());
    this.bump();
  }
  insertTable(rows = 3, cols = 3): void {
    this.controller.createTable(this.viewportCenterScene(), rows, cols);
    this.bump();
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

  render(ctx: RenderContext, width: number, height: number): void {
    this.canvasWidth = width;
    this.canvasHeight = height;
    renderScene(ctx, this.scene, { viewport: this.viewport, width, height, theme: this.theme });
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
