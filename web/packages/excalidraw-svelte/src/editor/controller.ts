import {
  BoundingBox,
  CropGeometry,
  DEFAULT_SNAP_DISTANCE,
  ElbowArrow,
  type RecognizedShape,
  type ShapeRecognition,
  ShapeRecognizer,
  bindableElementAt,
  commonBounds,
  bounds as elementBounds,
  fixedPointFor,
  flippedHeading,
  frameChildren,
  frameContaining,
  gapSnap,
  headingFromBoxToward,
  hit,
  isBindable,
  isFrame,
  snap as objectSnap,
  pointForFixedPoint,
} from "../geometry/index.js";
import { Point } from "../math/index.js";
import {
  type ArrowElement,
  type BaseProperties,
  type BinaryFileData,
  type ExcalidrawElement,
  type FixedPointBinding,
  type FixedSegment,
  type ImageCrop,
  type JSONValue,
  type LocalPoint,
  RoundnessType,
  Scene,
  Store,
  type TextElement,
  decodeFile,
  defaultTextProps,
  encodeFile,
  makeFile,
} from "../model/index.js";
import { measureTextWidth } from "../text-measure.js";
import { type CurrentItem, defaultCurrentItem, makeBase } from "./current-item.js";
import { parseMermaid } from "./mermaid.js";
import type { PointerEvent, PointerType } from "./pointer-event.js";
import { type Tool, toolElementType } from "./tool.js";
import { MIN_SIZE, Transform, type TransformHandle } from "./transform.js";

type Originals = Map<string, ExcalidrawElement>;

type Interaction =
  | { kind: "idle" }
  | { kind: "creating"; id: string; origin: Point; moved: boolean }
  | { kind: "freehand"; id: string; origin: Point }
  | { kind: "erasing" }
  | { kind: "moving"; origin: Point; originals: Originals }
  | { kind: "boxSelecting"; origin: Point }
  | { kind: "draggingLinearPoint"; id: string; index: number }
  | { kind: "resizing"; handle: TransformHandle; bounds: BoundingBox; originals: Originals }
  | { kind: "rotating"; center: Point; originals: Originals };

export type ZOrder = "front" | "back" | "forward" | "backward";
export type Alignment = "left" | "centerX" | "right" | "top" | "centerY" | "bottom";
export type FlowchartDirection = "up" | "down" | "left" | "right";

/**
 * The editing state machine: turns scene-space pointer events into element
 * creation, selection, move, resize, and rotation, with undo/redo. Pure TS (no
 * DOM). (parity: EditorController.swift)
 */
export class EditorController {
  store: Store;
  activeTool: Tool = "selection";
  toolLocked = false;
  currentItem: CurrentItem = defaultCurrentItem();
  zoom = 1;
  selectedIDs = new Set<string>();
  selectionRect: BoundingBox | null = null;
  snapEnabled = false;
  bindingEnabled = true;
  snapLinesX: number[] = [];
  snapLinesY: number[] = [];
  /** The line/arrow currently in point-edit mode (`null` when not editing). */
  editingLinearID: string | null = null;
  /** The image currently in crop mode (`null` when not cropping). */
  editingCropID: string | null = null;

  private elbowDrag: { id: string; index: number } | null = null;
  private cropNaturalSize: { width: number; height: number } | null = null;
  private cropDrag: {
    handle: TransformHandle;
    startBox: BoundingBox;
    startCrop: ImageCrop;
    fullBox: BoundingBox;
  } | null = null;
  private interaction: Interaction = { kind: "idle" };
  private readonly nextID: () => string;
  private readonly nextSeed: () => number;
  /** Monotonic counter behind the default `el-N` id generator, seeded past any
   * ids already in the scene (a loaded document / autosave / sample). */
  private idCounter = 0;
  /**
   * Prefix for generated element ids. Set to a per-client value (e.g. the peer
   * id) during collaboration so two clients never mint colliding ids — a
   * collision would make one client's new element lose reconciliation against
   * the other's same-id element.
   */
  idPrefix = "";

  constructor(scene: Scene = new Scene(), idProvider?: () => string, seedProvider?: () => number) {
    this.store = new Store(scene);
    let seedCounter = 1;
    // Seed past any `el-N` ids already in the scene: a loaded document / autosave
    // / sample uses the same scheme, so a counter restarting at el-1 collides —
    // producing two elements with one id (phantom copy on move, un-deletable,
    // oversized selection).
    this.idCounter = EditorController.maxElNumber(scene, this.idPrefix);
    this.nextID = idProvider ?? (() => `${this.idPrefix}el-${++this.idCounter}`);
    this.nextSeed = seedProvider ?? (() => ++seedCounter * 100_001);
  }

  /** Highest `<prefix>el-N` number present in `scene` (0 if none). */
  private static maxElNumber(scene: Scene, prefix: string): number {
    const token = `${prefix}el-`;
    let max = 0;
    for (const el of scene.elements) {
      if (!el.id.startsWith(token)) continue;
      const n = Number.parseInt(el.id.slice(token.length), 10);
      if (Number.isInteger(n)) max = Math.max(max, n);
    }
    return max;
  }

  get scene(): Scene {
    return this.store.scene;
  }
  get canUndo(): boolean {
    return this.store.canUndo;
  }
  get canRedo(): boolean {
    return this.store.canRedo;
  }
  get selectedElements(): ExcalidrawElement[] {
    return this.scene.visibleElements.filter((el) => this.selectedIDs.has(el.id));
  }
  get selectionBounds(): BoundingBox | null {
    return commonBounds(this.selectedElements);
  }
  get selectionOrContentBounds(): BoundingBox | null {
    return this.selectionBounds ?? commonBounds(this.scene.visibleElements);
  }

  /** Handle positions for the current selection (empty unless the selection tool is active). */
  transformHandles(): Map<TransformHandle, Point> {
    const bounds = this.selectionBounds;
    if (
      this.editingLinearID !== null ||
      this.editingCropID !== null ||
      this.activeTool !== "selection" ||
      bounds === null
    ) {
      return new Map();
    }
    return Transform.handlePositions(bounds, this.rotationOffset);
  }

  // MARK: Pointer handling

  pointerDown(e: PointerEvent): void {
    this.selectionRect = null;
    if (this.editingCropID !== null && this.handleCropEditDown(e)) return;
    if (this.editingLinearID !== null && this.handleLinearEditDown(e)) return;
    if (this.activeTool === "eraser") {
      this.interaction = { kind: "erasing" };
      this.eraseAt(e.scenePoint, e.type);
      return;
    }
    if (this.activeTool === "hand") return;
    const type = toolElementType(this.activeTool);
    if (type !== null) this.beginCreating(type, e.scenePoint, e.pressure);
    else this.beginSelectionInteraction(e);
  }

  pointerMove(e: PointerEvent): void {
    if (this.cropDrag !== null) {
      this.moveCropDrag(e.scenePoint);
      return;
    }
    if (this.elbowDrag !== null) {
      const newIndex = this.moveElbowSegment(this.elbowDrag.id, this.elbowDrag.index, e.scenePoint);
      this.elbowDrag = { id: this.elbowDrag.id, index: newIndex };
      return;
    }
    const i = this.interaction;
    switch (i.kind) {
      case "creating":
        this.updateCreating(i.id, i.origin, e.scenePoint);
        this.interaction = { ...i, moved: true };
        break;
      case "freehand":
        this.appendFreehandPoint(i.id, i.origin, e.scenePoint, e.pressure);
        break;
      case "draggingLinearPoint":
        this.moveLinearPoint(i.id, i.index, e.scenePoint);
        break;
      case "erasing":
        this.eraseAt(e.scenePoint, e.type);
        break;
      case "moving": {
        let dx = e.scenePoint.x - i.origin.x;
        let dy = e.scenePoint.y - i.origin.y;
        if (this.snapEnabled && !e.alt) {
          [dx, dy] = this.applyObjectSnap(i.originals, dx, dy);
        } else {
          this.snapLinesX = [];
          this.snapLinesY = [];
        }
        this.store.modifyScene((scene) => {
          for (const original of i.originals.values()) {
            scene.replace(Transform.translate(original, dx, dy));
          }
          if (this.bindingEnabled) updateBoundArrows(scene, new Set(i.originals.keys()));
        });
        break;
      }
      case "boxSelecting":
        this.selectionRect = boxOf(i.origin, e.scenePoint);
        break;
      case "resizing": {
        const next = Transform.resize(i.bounds, i.handle, e.scenePoint, e.shift, e.alt);
        this.store.modifyScene((scene) => {
          for (const original of i.originals.values()) {
            scene.replace(Transform.scale(original, i.bounds, next));
          }
          if (this.bindingEnabled) updateBoundArrows(scene, new Set(i.originals.keys()));
        });
        break;
      }
      case "rotating": {
        const angle = Transform.rotationAngle(i.center, e.scenePoint, e.shift);
        this.store.modifyScene((scene) => {
          for (const original of i.originals.values()) scene.replace({ ...original, angle });
        });
        break;
      }
      default:
        break;
    }
  }

  pointerUp(e: PointerEvent): void {
    if (this.cropDrag !== null) {
      this.cropDrag = null;
      this.store.commit();
      return;
    }
    if (this.elbowDrag !== null) {
      this.elbowDrag = null;
      this.store.commit();
      return;
    }
    const i = this.interaction;
    switch (i.kind) {
      case "creating":
        this.finishCreating(i.id, i.moved);
        break;
      case "freehand":
        this.finishFreehand();
        break;
      case "draggingLinearPoint":
        this.store.commit();
        break;
      case "erasing":
        this.store.commit();
        this.selectedIDs = new Set();
        break;
      case "moving":
        this.snapLinesX = [];
        this.snapLinesY = [];
        this.reassignFrameMembership(new Set(i.originals.keys()));
        this.store.commit();
        break;
      case "resizing":
      case "rotating":
        this.snapLinesX = [];
        this.snapLinesY = [];
        this.store.commit();
        break;
      case "boxSelecting":
        this.selectWithin(boxOf(i.origin, e.scenePoint), e.toggleSelection);
        this.selectionRect = null;
        break;
      default:
        break;
    }
    this.interaction = { kind: "idle" };
  }

  // MARK: Commands

  load(scene: Scene): void {
    this.store = new Store(scene);
    this.idCounter = Math.max(this.idCounter, EditorController.maxElNumber(scene, this.idPrefix));
    this.selectedIDs = new Set();
    this.interaction = { kind: "idle" };
  }

  setTool(tool: Tool): void {
    this.activeTool = tool;
    this.exitLinearEdit();
    this.exitCropEdit();
  }

  // MARK: Image cropping

  /** Enter crop mode for image `id`; the UI supplies the natural pixel size. */
  beginCropEdit(id: string, naturalWidth: number, naturalHeight: number): boolean {
    const el = this.scene.element(id);
    if (el === undefined || el.type !== "image" || naturalWidth <= 0 || naturalHeight <= 0)
      return false;
    this.editingCropID = id;
    this.cropNaturalSize = { width: naturalWidth, height: naturalHeight };
    this.selectedIDs = new Set([id]);
    return true;
  }

  exitCropEdit(): void {
    this.editingCropID = null;
    this.cropNaturalSize = null;
    this.cropDrag = null;
  }

  /** The topmost image hit at `point`, with its data URL (to enter crop mode). */
  imageHit(point: Point): { id: string; dataURL: string } | null {
    const threshold = this.handleHitRadius("mouse");
    const visible = this.scene.visibleElements;
    for (let k = visible.length - 1; k >= 0; k--) {
      const el = visible[k]!;
      if (el.locked || el.type !== "image" || el.fileId === null) continue;
      const file = this.scene.files[el.fileId];
      if (file !== undefined && hit(el, point, threshold))
        return { id: el.id, dataURL: file.dataURL };
    }
    return null;
  }

  /** The current display box of the image being cropped. */
  cropFrame(): BoundingBox | null {
    const id = this.editingCropID;
    const el = id === null ? undefined : this.scene.element(id);
    if (el === undefined) return null;
    return new BoundingBox(el.x, el.y, el.x + el.width, el.y + el.height);
  }

  /** The eight handle positions framing the image being cropped (for the overlay). */
  cropEditHandles(): Point[] | null {
    const frame = this.cropFrame();
    if (frame === null) return null;
    const handles = Transform.handlePositions(frame, 0);
    handles.delete("rotation");
    return [...handles.values()];
  }

  private effectiveCrop(el: ExcalidrawElement): ImageCrop | null {
    if (el.type !== "image") return null;
    if (el.crop !== null) return el.crop;
    if (this.cropNaturalSize === null) return null;
    return CropGeometry.fullCrop(this.cropNaturalSize.width, this.cropNaturalSize.height);
  }

  private handleCropEditDown(e: PointerEvent): boolean {
    const id = this.editingCropID;
    const el = id === null ? undefined : this.scene.element(id);
    const frame = this.cropFrame();
    const crop = el === undefined ? null : this.effectiveCrop(el);
    if (el === undefined || frame === null || crop === null) {
      this.exitCropEdit();
      return false;
    }
    const threshold = this.handleHitRadius(e.type);
    const handles = Transform.handlePositions(frame, 0);
    handles.delete("rotation");
    for (const [handle, position] of handles) {
      if (position.distance(e.scenePoint) <= threshold) {
        this.cropDrag = {
          handle,
          startBox: frame,
          startCrop: crop,
          fullBox: CropGeometry.fullImageBox(frame, crop),
        };
        return true;
      }
    }
    this.exitCropEdit();
    return false;
  }

  private moveCropDrag(point: Point): void {
    const drag = this.cropDrag;
    const id = this.editingCropID;
    const el = id === null ? undefined : this.scene.element(id);
    if (drag === null || el === undefined || el.type !== "image") return;
    const resized = Transform.resize(drag.startBox, drag.handle, point);
    const newBox = CropGeometry.clampBox(resized, drag.fullBox);
    const crop = CropGeometry.updatedCrop(drag.startBox, drag.startCrop, newBox);
    this.store.modifyScene((scene) =>
      scene.replace({
        ...el,
        crop,
        x: newBox.minX,
        y: newBox.minY,
        width: newBox.width,
        height: newBox.height,
      }),
    );
  }

  // MARK: Linear point editing

  /** Enter point-edit mode for the line/arrow hit at `point`. */
  beginLinearEdit(point: Point): boolean {
    const threshold = this.handleHitRadius("mouse");
    const visible = this.scene.visibleElements;
    for (let k = visible.length - 1; k >= 0; k--) {
      const el = visible[k]!;
      if (!el.locked && linearPointsOf(el) !== null && hit(el, point, threshold)) {
        this.editingLinearID = el.id;
        this.selectedIDs = new Set([el.id]);
        return true;
      }
    }
    return false;
  }

  exitLinearEdit(): void {
    this.editingLinearID = null;
    this.elbowDrag = null;
  }

  /** Global vertex + midpoint positions for the line being edited (for the overlay). */
  linearEditHandles(): { points: Point[]; midpoints: Point[] } | null {
    const id = this.editingLinearID;
    if (id === null) return null;
    const el = this.scene.element(id);
    const pts = el === undefined ? null : linearPointsOf(el);
    if (el === undefined || pts === null) return null;
    const points = pts.map((p) => new Point(el.x + p[0], el.y + p[1]));
    const midpoints: Point[] = [];
    for (let i = 0; i < points.length - 1; i++) midpoints.push(points[i]!.midpoint(points[i + 1]!));
    return { points, midpoints };
  }

  private handleLinearEditDown(e: PointerEvent): boolean {
    const id = this.editingLinearID;
    if (id === null) return false;
    const el = this.scene.element(id);
    const pts = el === undefined ? null : linearPointsOf(el);
    if (el === undefined || pts === null) {
      this.exitLinearEdit();
      return false;
    }
    const threshold = this.handleHitRadius(e.type);
    // Elbow arrows are reshaped by dragging whole segments, not vertices.
    if (el.type === "arrow" && el.elbowed) {
      for (const handle of this.elbowSegmentHandles(id)) {
        if (handle.point.distance(e.scenePoint) <= threshold) {
          this.elbowDrag = { id, index: handle.index };
          return true;
        }
      }
      this.exitLinearEdit();
      return false;
    }
    for (let i = 0; i < pts.length; i++) {
      const global = new Point(el.x + pts[i]![0], el.y + pts[i]![1]);
      if (global.distance(e.scenePoint) <= threshold) {
        this.interaction = { kind: "draggingLinearPoint", id, index: i };
        return true;
      }
    }
    for (let i = 0; i < Math.max(0, pts.length - 1); i++) {
      const a = new Point(el.x + pts[i]![0], el.y + pts[i]![1]);
      const b = new Point(el.x + pts[i + 1]![0], el.y + pts[i + 1]![1]);
      if (a.midpoint(b).distance(e.scenePoint) <= threshold) {
        const next: LocalPoint[] = [...pts];
        next.splice(i + 1, 0, [e.scenePoint.x - el.x, e.scenePoint.y - el.y]);
        this.store.modifyScene((scene) => scene.replace(setLinearPoints(next, el)));
        this.interaction = { kind: "draggingLinearPoint", id, index: i + 1 };
        return true;
      }
    }
    this.exitLinearEdit();
    return false;
  }

  private moveLinearPoint(id: string, index: number, point: Point): void {
    const el = this.scene.element(id);
    const pts = el === undefined ? null : linearPointsOf(el);
    if (el === undefined || pts === null || index < 0 || index >= pts.length) return;
    const next: LocalPoint[] = [...pts];
    next[index] = [point.x - el.x, point.y - el.y];
    this.store.modifyScene((scene) => scene.replace(setLinearPoints(next, el)));
  }

  selectAll(): void {
    this.selectedIDs = new Set(this.scene.visibleElements.map((el) => el.id));
  }

  clearSelection(): void {
    this.selectedIDs = new Set();
  }

  deleteSelected(): void {
    if (this.selectedIDs.size === 0) return;
    const removed = this.withBoundText(this.selectedIDs);
    this.store.transaction((scene) => {
      for (const id of removed) scene.remove(id);
      EditorController.dropDanglingRefs(scene, removed);
    });
    this.selectedIDs = new Set();
  }

  /** A selection expanded to include the bound text of every selected container,
   * so deleting a labeled shape / sticky note / table cell removes its label too
   * instead of orphaning it on screen. */
  private withBoundText(ids: Set<string>): Set<string> {
    const out = new Set<string>(ids);
    for (const id of ids) {
      const el = this.scene.element(id);
      for (const b of el?.boundElements ?? []) {
        if (b.type === "text") out.add(b.id);
      }
    }
    return out;
  }

  /** Strip references to `removed` ids from surviving elements — bound-element
   * lists and arrow start/end bindings — so nothing points at a deleted element. */
  private static dropDanglingRefs(scene: Scene, removed: Set<string>): void {
    for (const el of scene.visibleElements) {
      let next = el;
      if (el.boundElements?.some((b) => removed.has(b.id))) {
        next = { ...next, boundElements: el.boundElements.filter((b) => !removed.has(b.id)) };
      }
      const b = next as {
        startBinding?: FixedPointBinding | null;
        endBinding?: FixedPointBinding | null;
      };
      if (b.startBinding && removed.has(b.startBinding.elementId)) {
        next = { ...next, startBinding: null } as ExcalidrawElement;
      }
      if (b.endBinding && removed.has(b.endBinding.elementId)) {
        next = { ...next, endBinding: null } as ExcalidrawElement;
      }
      if (next !== el) scene.replace(next);
    }
  }

  /** Apply a change to every selected element as one undo step. */
  updateSelected(change: (draft: ExcalidrawElement) => void): void {
    if (this.selectedIDs.size === 0) return;
    this.store.transaction((scene) => {
      for (const id of this.selectedIDs) {
        const current = scene.element(id);
        if (current === undefined) continue;
        const draft = structuredClone(current);
        change(draft);
        scene.replace(draft);
      }
    });
  }

  undo(): boolean {
    const ok = this.store.undo();
    this.pruneSelection();
    return ok;
  }

  redo(): boolean {
    const ok = this.store.redo();
    this.pruneSelection();
    return ok;
  }

  // MARK: Actions (group / duplicate / align / flip / z-order / lock)

  group(): void {
    if (this.selectedIDs.size <= 1) return;
    const groupID = this.nextID();
    this.updateSelected((el) => {
      el.groupIds = [...el.groupIds, groupID];
    });
  }

  ungroup(): void {
    this.updateSelected((el) => {
      if (el.groupIds.length > 0) el.groupIds = el.groupIds.slice(0, -1);
    });
  }

  duplicate(): void {
    const originals = this.selectedElements;
    if (originals.length === 0) return;
    const newIDs: string[] = [];
    this.store.transaction((scene) => {
      for (const original of originals) {
        const copy = structuredClone(original);
        copy.id = this.nextID();
        copy.x += 10;
        copy.y += 10;
        scene.add(copy);
        newIDs.push(copy.id);
      }
    });
    this.selectedIDs = new Set(newIDs);
  }

  setLocked(locked: boolean): void {
    this.updateSelected((el) => {
      el.locked = locked;
    });
  }

  reorder(order: ZOrder): void {
    if (this.selectedIDs.size === 0) return;
    const selected = this.selectedIDs;
    this.store.transaction((scene) => {
      let elements = [...scene.elements];
      if (order === "front") {
        const moving = elements.filter((e) => selected.has(e.id));
        elements = elements.filter((e) => !selected.has(e.id));
        elements.push(...moving);
      } else if (order === "back") {
        const moving = elements.filter((e) => selected.has(e.id));
        elements = elements.filter((e) => !selected.has(e.id));
        elements.unshift(...moving);
      } else if (order === "forward") {
        for (let k = elements.length - 2; k >= 0; k--) {
          if (selected.has(elements[k]!.id) && !selected.has(elements[k + 1]!.id)) {
            [elements[k], elements[k + 1]] = [elements[k + 1]!, elements[k]!];
          }
        }
      } else {
        for (let k = 1; k < elements.length; k++) {
          if (selected.has(elements[k]!.id) && !selected.has(elements[k - 1]!.id)) {
            [elements[k], elements[k - 1]] = [elements[k - 1]!, elements[k]!];
          }
        }
      }
      scene.replaceAll(elements);
    });
  }

  align(alignment: Alignment): void {
    const group = this.selectionBounds;
    if (this.selectedElements.length <= 1 || group === null) return;
    this.updateSelected((el) => {
      const b = elementBounds(el);
      switch (alignment) {
        case "left":
          el.x += group.minX - b.minX;
          break;
        case "right":
          el.x += group.maxX - b.maxX;
          break;
        case "centerX":
          el.x += (group.minX + group.maxX) / 2 - (b.minX + b.maxX) / 2;
          break;
        case "top":
          el.y += group.minY - b.minY;
          break;
        case "bottom":
          el.y += group.maxY - b.maxY;
          break;
        case "centerY":
          el.y += (group.minY + group.maxY) / 2 - (b.minY + b.maxY) / 2;
          break;
      }
    });
  }

  flip(horizontal: boolean): void {
    const bounds = this.selectionBounds;
    if (bounds === null) return;
    this.updateSelected((el) => {
      const b = elementBounds(el);
      if (horizontal) el.x = bounds.minX + bounds.maxX - b.maxX;
      else el.y = bounds.minY + bounds.maxY - b.maxY;
      flipPoints(el, horizontal);
    });
  }

  // MARK: Interaction helpers

  private beginCreating(type: string, origin: Point, pressure: number): void {
    const base = makeBase(this.currentItem, this.nextID(), this.nextSeed(), origin.x, origin.y);
    let element: ExcalidrawElement;
    switch (type) {
      case "line":
        element = {
          ...base,
          type: "line",
          points: [
            [0, 0],
            [0, 0],
          ],
          startBinding: null,
          endBinding: null,
          startArrowhead: null,
          endArrowhead: null,
          polygon: false,
        };
        break;
      case "arrow":
        element = {
          ...base,
          type: "arrow",
          points: [
            [0, 0],
            [0, 0],
          ],
          startBinding: null,
          endBinding: null,
          startArrowhead: this.currentItem.startArrowhead,
          endArrowhead: this.currentItem.endArrowhead,
          elbowed: this.currentItem.elbowed,
        };
        break;
      case "freedraw": {
        const free: ExcalidrawElement = {
          ...base,
          type: "freedraw",
          points: [[0, 0]],
          pressures: [pressure],
          simulatePressure: false,
        };
        this.store.modifyScene((scene) => scene.add(free));
        this.selectedIDs = new Set([free.id]);
        this.interaction = { kind: "freehand", id: free.id, origin };
        return;
      }
      case "frame":
        element = { ...base, type: "frame", name: null };
        break;
      default:
        element = { ...base, type: type as "rectangle" | "diamond" | "ellipse" };
        break;
    }
    if (this.currentItem.roundEdges) {
      const roundness = roundnessType(type);
      if (roundness !== null) element.roundness = { type: roundness };
    }
    this.store.modifyScene((scene) => scene.add(element));
    this.selectedIDs = new Set([element.id]);
    this.interaction = { kind: "creating", id: element.id, origin, moved: false };
  }

  private updateCreating(id: string, origin: Point, point: Point): void {
    const el = this.scene.element(id);
    if (el === undefined) return;
    const endpoint: LocalPoint = [point.x - origin.x, point.y - origin.y];
    let updated: ExcalidrawElement;
    if (el.type === "line" || el.type === "arrow") {
      updated = {
        ...el,
        x: origin.x,
        y: origin.y,
        width: Math.abs(endpoint[0]),
        height: Math.abs(endpoint[1]),
        points: [[0, 0], endpoint],
      };
    } else {
      updated = {
        ...el,
        x: Math.min(origin.x, point.x),
        y: Math.min(origin.y, point.y),
        width: Math.abs(point.x - origin.x),
        height: Math.abs(point.y - origin.y),
      };
    }
    this.store.modifyScene((scene) => scene.replace(updated));
  }

  private finishCreating(id: string, moved: boolean): void {
    const el = this.scene.element(id);
    const tiny = (el?.width ?? 0) < MIN_SIZE && (el?.height ?? 0) < MIN_SIZE;
    if (!moved || tiny) {
      this.store.modifyScene((scene) =>
        scene.replaceAll(scene.elements.filter((e) => e.id !== id)),
      );
      this.selectedIDs = new Set();
    } else {
      if (this.bindingEnabled) this.bindArrowEndpoints(id);
      this.routeElbowArrow(id);
      this.reassignFrameMembership(new Set([id]));
      this.store.commit();
      if (!this.toolLocked) this.activeTool = "selection";
    }
  }

  /** If the element is an arrow, bind its endpoints to nearby bindable shapes. */
  bindArrowEndpoints(id: string): void {
    this.store.modifyScene((scene) => {
      const arrow = scene.element(id);
      if (arrow === undefined || arrow.type !== "arrow") return;
      const first = arrow.points[0];
      const last = arrow.points[arrow.points.length - 1];
      if (first === undefined || last === undefined) return;
      const startGlobal = new Point(arrow.x + first[0], arrow.y + first[1]);
      const endGlobal = new Point(arrow.x + last[0], arrow.y + last[1]);
      const others = scene.visibleElements;
      const exclude = new Set([id]);
      let { startBinding, endBinding } = arrow;

      const startTarget = bindableElementAt(startGlobal, others, exclude);
      if (startTarget !== null) {
        startBinding = {
          elementId: startTarget.id,
          fixedPoint: fixedPointFor(startGlobal, elementBounds(startTarget)).toArray(),
          mode: "orbit",
        };
        addBoundArrow(scene, id, startTarget.id);
      }
      const endTarget = bindableElementAt(endGlobal, others, exclude);
      if (endTarget !== null) {
        endBinding = {
          elementId: endTarget.id,
          fixedPoint: fixedPointFor(endGlobal, elementBounds(endTarget)).toArray(),
          mode: "orbit",
        };
        addBoundArrow(scene, id, endTarget.id);
      }
      scene.replace({ ...arrow, startBinding, endBinding });
    });
  }

  private appendFreehandPoint(id: string, origin: Point, point: Point, pressure: number): void {
    const el = this.scene.element(id);
    if (el === undefined || el.type !== "freedraw") return;
    const points: LocalPoint[] = [...el.points, [point.x - origin.x, point.y - origin.y]];
    const xs = points.map((p) => p[0]);
    const ys = points.map((p) => p[1]);
    this.store.modifyScene((scene) =>
      scene.replace({
        ...el,
        points,
        pressures: [...el.pressures, pressure],
        width: Math.max(...xs) - Math.min(...xs),
        height: Math.max(...ys) - Math.min(...ys),
      }),
    );
  }

  private finishFreehand(): void {
    this.store.commit();
    if (!this.toolLocked) this.activeTool = "selection";
  }

  private applyObjectSnap(originals: Originals, dx: number, dy: number): [number, number] {
    const moved = [...originals.values()].map((el) => Transform.translate(el, dx, dy));
    const movingBounds = commonBounds(moved);
    if (movingBounds === null) {
      this.snapLinesX = [];
      this.snapLinesY = [];
      return [dx, dy];
    }
    const movingIDs = new Set(originals.keys());
    const statics = this.scene.visibleElements
      .filter((el) => !movingIDs.has(el.id))
      .map((el) => elementBounds(el));
    const threshold = DEFAULT_SNAP_DISTANCE / this.zoom;
    const result = objectSnap(movingBounds, statics, threshold);
    let offsetX = result.offsetX;
    let offsetY = result.offsetY;
    let linesX = result.verticalLines;
    let linesY = result.horizontalLines;

    const gap = gapSnap(movingBounds, statics, threshold);
    if (linesX.length === 0 && gap.verticalLines.length > 0) {
      offsetX = gap.offsetX;
      linesX = gap.verticalLines;
    }
    if (linesY.length === 0 && gap.horizontalLines.length > 0) {
      offsetY = gap.offsetY;
      linesY = gap.horizontalLines;
    }
    this.snapLinesX = linesX;
    this.snapLinesY = linesY;
    return [dx + offsetX, dy + offsetY];
  }

  private eraseAt(point: Point, type: PointerType): void {
    const threshold = this.handleHitRadius(type);
    const hits = this.scene.visibleElements.filter((el) => !el.locked && hit(el, point, threshold));
    if (hits.length === 0) return;
    this.store.modifyScene((scene) => {
      for (const h of hits) scene.remove(h.id);
    });
  }

  private beginSelectionInteraction(e: PointerEvent): void {
    const point = e.scenePoint;
    const bounds = this.selectionBounds;
    if (bounds !== null) {
      for (const [handle, position] of Transform.handlePositions(bounds, this.rotationOffset)) {
        if (position.distance(point) <= this.handleHitRadius(e.type)) {
          const originals = this.snapshotSelected();
          this.interaction =
            handle === "rotation"
              ? {
                  kind: "rotating",
                  center: new Point(
                    (bounds.minX + bounds.maxX) / 2,
                    (bounds.minY + bounds.maxY) / 2,
                  ),
                  originals,
                }
              : { kind: "resizing", handle, bounds, originals };
          return;
        }
      }
    }

    const hitID = this.topElement(point, e.type);
    if (hitID !== null) {
      const group = this.groupSiblings(hitID);
      if (e.toggleSelection) {
        if (isSuperset(this.selectedIDs, group)) {
          for (const id of group) this.selectedIDs.delete(id);
        } else {
          for (const id of group) this.selectedIDs.add(id);
        }
      } else if (!this.selectedIDs.has(hitID)) {
        this.selectedIDs = new Set(group);
      }
      this.interaction = { kind: "moving", origin: point, originals: this.snapshotForMove() };
    } else {
      if (!e.toggleSelection) this.selectedIDs = new Set();
      this.interaction = { kind: "boxSelecting", origin: point };
      this.selectionRect = new BoundingBox(point.x, point.y, point.x, point.y);
    }
  }

  private snapshotSelected(): Originals {
    return new Map(this.selectedElements.map((el) => [el.id, el]));
  }

  private snapshotForMove(): Originals {
    const result = this.snapshotSelected();
    const add = (el: ExcalidrawElement | undefined): void => {
      if (el !== undefined) result.set(el.id, el);
    };
    for (const el of this.selectedElements) {
      // A move drags the whole group, not just the hit member.
      for (const id of this.groupSiblings(el.id)) add(this.scene.element(id));
      // Frames carry their children.
      if (isFrame(el)) {
        for (const child of frameChildren(el.id, this.scene.visibleElements)) add(child);
      }
      // Container-bound text (e.g. a sticky-note label) moves with its container;
      // otherwise it strands at its old position and inflates the group's bounds.
      for (const b of el.boundElements ?? []) {
        if (b.type === "text") add(this.scene.element(b.id));
      }
    }
    return result;
  }

  private reassignFrameMembership(ids: Set<string>): void {
    this.store.modifyScene((scene) => {
      for (const id of ids) {
        const el = scene.element(id);
        if (el === undefined || isFrame(el)) continue;
        const frameId = frameContaining(el, scene.visibleElements);
        if (el.frameId !== frameId) scene.replace({ ...el, frameId });
      }
    });
  }

  private topElement(point: Point, type: PointerType): string | null {
    const threshold = this.handleHitRadius(type);
    const visible = this.scene.visibleElements;
    for (let k = visible.length - 1; k >= 0; k--) {
      const el = visible[k]!;
      if (!el.locked && hit(el, point, threshold)) return el.id;
    }
    return null;
  }

  private selectWithin(rect: BoundingBox, additive: boolean): void {
    const within = this.scene.visibleElements
      .filter((el) => {
        const b = elementBounds(el);
        return (
          b.minX >= rect.minX && b.maxX <= rect.maxX && b.minY >= rect.minY && b.maxY <= rect.maxY
        );
      })
      .flatMap((el) => [...this.groupSiblings(el.id)]);
    if (additive) for (const id of within) this.selectedIDs.add(id);
    else this.selectedIDs = new Set(within);
  }

  groupSiblings(id: string): Set<string> {
    const el = this.scene.element(id);
    const group = el?.groupIds[el.groupIds.length - 1];
    if (el === undefined || group === undefined) return new Set([id]);
    const siblings = this.scene.visibleElements
      .filter((e) => e.groupIds.includes(group))
      .map((e) => e.id);
    return new Set([...siblings, id]);
  }

  private pruneSelection(): void {
    const live = new Set(this.scene.visibleElements.map((el) => el.id));
    this.selectedIDs = new Set([...this.selectedIDs].filter((id) => live.has(id)));
  }

  private handleHitRadius(type: PointerType): number {
    const px = type === "touch" ? 28 : type === "pen" ? 16 : 10;
    return px / this.zoom;
  }

  private get rotationOffset(): number {
    return 30 / this.zoom;
  }

  // MARK: Commands — links, clipboard, text, image

  static readonly stickyNoteColor = "#ffec99";

  /** Set (or clear, with null/empty) a hyperlink on the selected elements. */
  setLink(url: string | null): void {
    const trimmed = url?.trim();
    this.updateSelected((el) => {
      el.link = trimmed === undefined || trimmed.length === 0 ? null : trimmed;
    });
  }

  /** The link of the single selected element, if any. */
  get selectionLink(): string | null {
    const sel = this.selectedElements;
    return sel.length === 1 ? (sel[0]!.link ?? null) : null;
  }

  /** Set (or clear) the crop rectangle on an image element, as one undo step. */
  setCrop(id: string, crop: ImageCrop | null): void {
    const el = this.scene.element(id);
    if (el === undefined || el.type !== "image") return;
    this.store.transaction((scene) => scene.replace({ ...el, crop }));
  }

  /** Serialize the selection as an `.excalidraw` payload string. */
  copyData(): string | null {
    const elements = this.selectedElements;
    if (elements.length === 0) return null;
    return encodeFile(makeFile({ elements, files: this.filesFor(elements) }));
  }

  /** Paste elements from an `.excalidraw` payload, offset and re-id'd, and select them. */
  paste(json: string, offset = 10): void {
    let elements: ExcalidrawElement[];
    let files: Record<string, BinaryFileData>;
    try {
      const file = decodeFile(json);
      elements = file.elements;
      files = file.files;
    } catch {
      return;
    }
    if (elements.length === 0) return;
    const newIDs: string[] = [];
    this.store.transaction((scene) => {
      for (const el of elements) {
        const copy = structuredClone(el);
        copy.id = this.nextID();
        copy.x += offset;
        copy.y += offset;
        scene.add(copy);
        newIDs.push(copy.id);
      }
      for (const [id, f] of Object.entries(files)) scene.files[id] = f;
    });
    this.selectedIDs = new Set(newIDs);
  }

  private filesFor(elements: ExcalidrawElement[]): Record<string, BinaryFileData> {
    const result: Record<string, BinaryFileData> = {};
    for (const el of elements) {
      if (el.type === "image" && el.fileId !== null) {
        const file = this.scene.files[el.fileId];
        if (file !== undefined) result[el.fileId] = file;
      }
    }
    return result;
  }

  /** Create an empty text element at `point` and select it; returns its id. */
  createText(point: Point, fontSize?: number): string {
    const base = makeBase(this.currentItem, this.nextID(), this.nextSeed(), point.x, point.y);
    const el: ExcalidrawElement = {
      ...base,
      type: "text",
      ...defaultTextProps({
        fontSize: fontSize ?? this.currentItem.fontSize,
        fontFamily: this.currentItem.fontFamily,
      }),
    };
    this.store.modifyScene((scene) => scene.add(el));
    this.selectedIDs = new Set([el.id]);
    return el.id;
  }

  /** Set a text element's content (one undo step), or remove it if empty and unbound. */
  setText(id: string, text: string): void {
    const el = this.scene.element(id);
    if (el === undefined || el.type !== "text") return;
    if (text.length === 0 && el.containerId === null) {
      this.store.modifyScene((scene) =>
        scene.replaceAll(scene.elements.filter((e) => e.id !== id)),
      );
      this.store.commit();
      this.selectedIDs.delete(id);
      return;
    }
    this.store.transaction((scene) => {
      const lines = text.split("\n");
      scene.replace({
        ...el,
        text,
        originalText: text,
        width: measureTextWidth(text, el.fontSize, el.fontFamily),
        height: lines.length * el.fontSize * el.lineHeight,
      });
    });
  }

  /** Apply a change to each selected text element, recomputing its size, as one undo step. */
  updateSelectedText(change: (draft: TextElement) => void): void {
    const ids = this.selectedElements.filter((e) => e.type === "text").map((e) => e.id);
    if (ids.length === 0) return;
    this.store.transaction((scene) => {
      for (const id of ids) {
        const el = scene.element(id);
        if (el === undefined || el.type !== "text") continue;
        const draft = structuredClone(el);
        change(draft);
        const lines = draft.text.split("\n");
        draft.width = measureTextWidth(draft.text, draft.fontSize, draft.fontFamily);
        draft.height = Math.max(1, lines.length) * draft.fontSize * draft.lineHeight;
        scene.replace(draft);
      }
    });
  }

  /** Insert an image element backed by a stored file, and select it. */
  insertImage(
    dataURL: string,
    mimeType: string,
    point: Point,
    width: number,
    height: number,
    created = 0,
  ): string {
    const fileId = this.nextID();
    const base = makeBase(this.currentItem, this.nextID(), this.nextSeed(), point.x, point.y);
    const el: ExcalidrawElement = {
      ...base,
      width,
      height,
      backgroundColor: "transparent",
      type: "image",
      fileId,
      status: "saved",
      scale: [1, 1],
      crop: null,
    };
    this.store.transaction((scene) => {
      scene.files[fileId] = { mimeType, id: fileId, dataURL, created };
      scene.add(el);
    });
    this.selectedIDs = new Set([el.id]);
    return el.id;
  }

  /** Insert an embeddable element carrying `link`, centred at `point`, and select it. */
  insertEmbeddable(link: string, point: Point, width = 460, height = 300): string {
    const base = makeBase(
      this.currentItem,
      this.nextID(),
      this.nextSeed(),
      point.x - width / 2,
      point.y - height / 2,
    );
    const el: ExcalidrawElement = {
      ...base,
      width,
      height,
      backgroundColor: "transparent",
      link,
      type: "embeddable",
    };
    this.store.modifyScene((scene) => scene.add(el));
    this.selectedIDs = new Set([el.id]);
    return el.id;
  }

  /** Stamp a library item onto the canvas with its top-left at `point`, re-id'd. */
  insertLibraryItem(elements: ExcalidrawElement[], point: Point): string[] {
    const live = elements.filter((e) => !e.isDeleted);
    const box = commonBounds(live);
    if (box === null) return [];
    const dx = point.x - box.minX;
    const dy = point.y - box.minY;
    const newIDs: string[] = [];
    this.store.transaction((scene) => {
      for (const el of live) {
        const copy = structuredClone(el);
        copy.id = this.nextID();
        copy.x += dx;
        copy.y += dy;
        scene.add(copy);
        newIDs.push(copy.id);
      }
    });
    this.selectedIDs = new Set(newIDs);
    return newIDs;
  }

  // MARK: Generators — sticky notes, tables, charts

  /** Create a sticky note (a filled rounded square + a centred bound text), grouped. */
  createStickyNote(point: Point, color?: string): { container: string; text: string } {
    const size = 160;
    const groupID = this.nextID();
    const containerID = this.nextID();
    const textID = this.nextID();

    const container: ExcalidrawElement = {
      ...makeBase(this.currentItem, containerID, this.nextSeed(), point.x, point.y),
      type: "rectangle",
      width: size,
      height: size,
      backgroundColor: color ?? EditorController.stickyNoteColor,
      fillStyle: "solid",
      roundness: { type: RoundnessType.adaptiveRadius },
      groupIds: [groupID],
      boundElements: [{ id: textID, type: "text" }],
    };
    const text: ExcalidrawElement = {
      ...makeBase(this.currentItem, textID, this.nextSeed(), point.x, point.y + size / 2),
      type: "text",
      ...defaultTextProps({
        fontSize: this.currentItem.fontSize,
        fontFamily: this.currentItem.fontFamily,
        textAlign: "center",
        verticalAlign: "middle",
        containerId: containerID,
        autoResize: false,
      }),
      backgroundColor: "transparent",
      groupIds: [groupID],
    };
    this.store.modifyScene((scene) => {
      scene.add(container);
      scene.add(text);
    });
    this.selectedIDs = new Set([containerID]);
    return { container: containerID, text: textID };
  }

  /** The text element bound to container `id`, if any. */
  boundTextID(id: string): string | null {
    const el = this.scene.element(id);
    return el?.boundElements?.find((b) => b.type === "text")?.id ?? null;
  }

  /** The topmost container with bound text hit at `point` (selects it). */
  boundTextHit(point: Point): { container: string; text: string } | null {
    const threshold = this.handleHitRadius("mouse");
    const visible = this.scene.visibleElements;
    for (let k = visible.length - 1; k >= 0; k--) {
      const el = visible[k]!;
      if (!el.locked && hit(el, point, threshold)) {
        const textID = this.boundTextID(el.id);
        if (textID !== null) {
          this.selectedIDs = new Set([el.id]);
          return { container: el.id, text: textID };
        }
      }
    }
    return null;
  }

  /** Create a `rows × cols` table with its top-left at `point`, grouped and selected. */
  createTable(point: Point, rows = 3, cols = 3): string {
    const r = Math.max(rows, 1);
    const c = Math.max(cols, 1);
    const cellW = 120;
    const cellH = 44;
    const groupID = this.nextID();
    this.store.transaction((scene) => {
      for (let row = 0; row < r; row++) {
        for (let col = 0; col < c; col++) {
          this.addTableCell(
            scene,
            groupID,
            point.x + col * cellW,
            point.y + row * cellH,
            cellW,
            cellH,
          );
        }
      }
    });
    this.selectedIDs = this.groupSiblings(this.tableCells(groupID)[0]?.id ?? "");
    return groupID;
  }

  addTableRow(groupID: string): void {
    const cells = this.tableCells(groupID);
    const any = cells[0];
    if (any === undefined) return;
    const columns = [...new Set(cells.map((cell) => cell.x))].sort((a, b) => a - b);
    const bottom = Math.max(...cells.map((cell) => cell.y + cell.height));
    this.store.transaction((scene) => {
      for (const x of columns) this.addTableCell(scene, groupID, x, bottom, any.width, any.height);
    });
  }

  addTableColumn(groupID: string): void {
    const cells = this.tableCells(groupID);
    const any = cells[0];
    if (any === undefined) return;
    const rows = [...new Set(cells.map((cell) => cell.y))].sort((a, b) => a - b);
    const right = Math.max(...cells.map((cell) => cell.x + cell.width));
    this.store.transaction((scene) => {
      for (const y of rows) this.addTableCell(scene, groupID, right, y, any.width, any.height);
    });
  }

  /** Whether `id` belongs to a table. */
  tableGroupID(id: string): string | null {
    const value = this.scene.element(id)?.customData?.table;
    return typeof value === "string" ? value : null;
  }

  private tableCells(group: string): ExcalidrawElement[] {
    return this.scene.visibleElements
      .filter((el) => el.customData?.table === group)
      .sort((a, b) => a.y - b.y || a.x - b.x);
  }

  private addTableCell(
    scene: Scene,
    group: string,
    x: number,
    y: number,
    width: number,
    height: number,
  ): void {
    const cellID = this.nextID();
    const textID = this.nextID();
    scene.add({
      ...makeBase(this.currentItem, cellID, this.nextSeed(), x, y),
      type: "rectangle",
      width,
      height,
      backgroundColor: "transparent",
      groupIds: [group],
      boundElements: [{ id: textID, type: "text" }],
      customData: { table: group },
    });
    scene.add({
      ...makeBase(this.currentItem, textID, this.nextSeed(), x, y + height / 2),
      type: "text",
      ...defaultTextProps({
        fontSize: 16,
        fontFamily: this.currentItem.fontFamily,
        textAlign: "center",
        verticalAlign: "middle",
        containerId: cellID,
        autoResize: false,
      }),
      backgroundColor: "transparent",
      groupIds: [group],
    });
  }

  /**
   * If `id` is a freedraw stroke that resembles a known shape, replace it with
   * that shape (preserving style) as one undo step and keep it selected.
   */
  recognizeFreedraw(id: string): RecognizedShape | null {
    const el = this.scene.element(id);
    if (el === undefined || el.type !== "freedraw") return null;
    const global = el.points.map((p) => new Point(el.x + p[0], el.y + p[1]));
    const recognition = ShapeRecognizer.recognize(global);
    if (recognition === null) return null;
    const replacement = this.applyRecognition(recognition, baseOf(el));
    this.store.transaction((scene) => scene.replace(replacement));
    this.selectedIDs = new Set([id]);
    return recognition.shape;
  }

  private applyRecognition(rec: ShapeRecognition, base: BaseProperties): ExcalidrawElement {
    const box = rec.bounds;
    if (rec.shape === "rectangle" || rec.shape === "ellipse" || rec.shape === "diamond") {
      return {
        ...base,
        x: box.minX,
        y: box.minY,
        width: box.width,
        height: box.height,
        type: rec.shape,
      };
    }
    if (rec.shape === "line") {
      return polylineElement(base, rec.vertices, false);
    }
    const closed = [...rec.vertices, rec.vertices[0] ?? Point.zero];
    return polylineElement(base, closed, true);
  }

  // MARK: Elbow arrows

  /** Re-route elbow arrow `id` from its current endpoints. */
  routeElbowArrow(id: string): void {
    this.store.modifyScene((scene) => {
      const arrow = scene.element(id);
      if (arrow === undefined || arrow.type !== "arrow" || !arrow.elbowed) return;
      const first = arrow.points[0];
      const last = arrow.points[arrow.points.length - 1];
      if (first === undefined || last === undefined) return;
      const startGlobal = new Point(arrow.x + first[0], arrow.y + first[1]);
      const endGlobal = new Point(arrow.x + last[0], arrow.y + last[1]);
      scene.replace(applyElbowRoute(scene, arrow, startGlobal, endGlobal));
    });
  }

  /** Set elbow mode for new arrows and convert any selected arrows, re-routing. */
  setElbowed(elbowed: boolean): void {
    this.currentItem.elbowed = elbowed;
    const arrowIDs = this.selectedElements.filter((e) => e.type === "arrow").map((e) => e.id);
    if (arrowIDs.length === 0) return;
    this.store.transaction((scene) => {
      for (const id of arrowIDs) {
        const arrow = scene.element(id);
        if (arrow === undefined || arrow.type !== "arrow" || arrow.elbowed === elbowed) continue;
        const first = arrow.points[0];
        const last = arrow.points[arrow.points.length - 1];
        if (first === undefined || last === undefined) continue;
        let updated: ArrowElement = { ...arrow, elbowed };
        if (elbowed) {
          const startGlobal = new Point(arrow.x + first[0], arrow.y + first[1]);
          const endGlobal = new Point(arrow.x + last[0], arrow.y + last[1]);
          updated = applyElbowRoute(scene, updated, startGlobal, endGlobal);
        }
        scene.replace(updated);
      }
    });
  }

  /** Global segment midpoints of elbow arrow `id` (for the edit overlay). */
  elbowSegmentHandles(id: string): { index: number; point: Point }[] {
    const el = this.scene.element(id);
    if (el === undefined || el.type !== "arrow" || !el.elbowed) return [];
    const global = el.points.map((p) => new Point(el.x + p[0], el.y + p[1]));
    return ElbowArrow.segments(global).map((s) => ({ index: s.index, point: s.midpoint }));
  }

  /** Drag segment `index` of elbow arrow `id` through `point`, pinning it. */
  moveElbowSegment(id: string, index: number, point: Point): number {
    let resultIndex = index;
    this.store.modifyScene((scene) => {
      const arrow = scene.element(id);
      if (arrow === undefined || arrow.type !== "arrow" || !arrow.elbowed) return;
      const global = arrow.points.map((p) => new Point(arrow.x + p[0], arrow.y + p[1]));
      const moved = ElbowArrow.moveSegment(global, index, point);
      resultIndex = moved.index;
      const origin = moved.points[0] ?? point;
      const points: LocalPoint[] = moved.points.map((p) => [p.x - origin.x, p.y - origin.y]);
      const xs = points.map((p) => p[0]);
      const ys = points.map((p) => p[1]);
      const updated: ArrowElement = {
        ...arrow,
        points,
        x: origin.x,
        y: origin.y,
        width: Math.max(...xs) - Math.min(...xs),
        height: Math.max(...ys) - Math.min(...ys),
      };
      if (moved.index < 0 || moved.index >= points.length) {
        scene.replace(updated);
        return;
      }
      const pinned: FixedSegment = {
        start: points[moved.index - 1]!,
        end: points[moved.index]!,
        index: moved.index,
      };
      const segments = (arrow.fixedSegments ?? []).slice();
      const existing = segments.findIndex((s) => s.index === moved.index);
      if (existing !== -1) segments[existing] = pinned;
      else {
        segments.push(pinned);
        segments.sort((a, b) => a.index - b.index);
      }
      scene.replace({ ...updated, fixedSegments: segments });
    });
    return resultIndex;
  }

  /** Release every pinned segment of elbow arrow `id` and re-route it. */
  resetElbowShape(id: string): void {
    const el = this.scene.element(id);
    if (
      el === undefined ||
      el.type !== "arrow" ||
      !el.elbowed ||
      (el.fixedSegments?.length ?? 0) === 0
    ) {
      return;
    }
    this.store.transaction((scene) => {
      const arrow = scene.element(id);
      if (arrow === undefined || arrow.type !== "arrow") return;
      const first = arrow.points[0];
      const last = arrow.points[arrow.points.length - 1];
      if (first === undefined || last === undefined) return;
      const cleared: ArrowElement = { ...arrow, fixedSegments: undefined };
      const startGlobal = new Point(arrow.x + first[0], arrow.y + first[1]);
      const endGlobal = new Point(arrow.x + last[0], arrow.y + last[1]);
      scene.replace(applyElbowRoute(scene, cleared, startGlobal, endGlobal));
    });
  }

  /** Whether elbow arrow `id` currently has any pinned segments. */
  hasFixedSegments(id: string): boolean {
    const el = this.scene.element(id);
    return el !== undefined && el.type === "arrow" && (el.fixedSegments?.length ?? 0) > 0;
  }

  // MARK: Flowchart spawning

  /** Spawn a node from `id` in `direction`, linked by a bound elbow arrow. */
  addFlowchartNode(
    id: string,
    direction: FlowchartDirection,
  ): { node: string; arrow: string } | null {
    const source = this.scene.element(id);
    if (source === undefined || !isBindable(source) || isLinearElement(source)) return null;
    const gap = 100;
    const offset =
      direction === "right"
        ? { x: source.width + gap, y: 0 }
        : direction === "left"
          ? { x: -(source.width + gap), y: 0 }
          : direction === "down"
            ? { x: 0, y: source.height + gap }
            : { x: 0, y: -(source.height + gap) };
    const stagger = this.flowchartStagger(source, direction);
    const nodeID = this.nextID();
    const newNode: ExcalidrawElement = {
      ...structuredClone(source),
      id: nodeID,
      seed: this.nextSeed(),
      x: source.x + offset.x + stagger.x,
      y: source.y + offset.y + stagger.y,
      boundElements: null,
      groupIds: [],
    };
    const arrowID = this.nextID();
    const arrow = this.makeBindingArrow(arrowID, source, newNode, direction);

    this.store.transaction((scene) => {
      scene.add(newNode);
      scene.add(arrow);
      addBoundArrow(scene, arrowID, id);
      addBoundArrow(scene, arrowID, nodeID);
      const routed = scene.element(arrowID);
      if (routed !== undefined && routed.type === "arrow") {
        const first = routed.points[0];
        const last = routed.points[routed.points.length - 1];
        if (first !== undefined && last !== undefined) {
          const startGlobal = new Point(routed.x + first[0], routed.y + first[1]);
          const endGlobal = new Point(routed.x + last[0], routed.y + last[1]);
          scene.replace(applyElbowRoute(scene, routed, startGlobal, endGlobal));
        }
      }
    });
    this.selectedIDs = new Set([nodeID]);
    return { node: nodeID, arrow: arrowID };
  }

  private flowchartStagger(
    source: ExcalidrawElement,
    direction: FlowchartDirection,
  ): { x: number; y: number } {
    const count = this.linkedNodeCount(source, direction);
    if (count <= 0) return { x: 0, y: 0 };
    const step = Math.floor((count + 1) / 2);
    const sign = count % 2 === 0 ? -1 : 1;
    const amount = step * sign;
    if (direction === "up" || direction === "down")
      return { x: (source.width + 100) * amount, y: 0 };
    return { x: 0, y: (source.height + 100) * amount };
  }

  private linkedNodeCount(source: ExcalidrawElement, direction: FlowchartDirection): number {
    const arrowIDs = new Set(
      (source.boundElements ?? []).filter((b) => b.type === "arrow").map((b) => b.id),
    );
    const box = elementBounds(source);
    let count = 0;
    for (const el of this.scene.visibleElements) {
      if (!arrowIDs.has(el.id) || el.type !== "arrow") continue;
      const first = el.points[0];
      const last = el.points[el.points.length - 1];
      if (first === undefined || last === undefined) continue;
      const start = new Point(el.x + first[0], el.y + first[1]);
      const end = new Point(el.x + last[0], el.y + last[1]);
      const outward = box.contains(start) ? end : start;
      if (headingFromBoxToward(box, outward) === direction) count++;
    }
    return count;
  }

  private makeBindingArrow(
    id: string,
    source: ExcalidrawElement,
    target: ExcalidrawElement,
    direction: FlowchartDirection,
  ): ArrowElement {
    const sBox = elementBounds(source);
    const tBox = elementBounds(target);
    const start = edgePoint(sBox, direction);
    const end = edgePoint(tBox, flippedHeading(direction) as FlowchartDirection);
    return {
      ...baseOf(source),
      id,
      seed: this.nextSeed(),
      x: start.x,
      y: start.y,
      width: Math.abs(end.x - start.x),
      height: Math.abs(end.y - start.y),
      backgroundColor: "transparent",
      boundElements: null,
      groupIds: [],
      type: "arrow",
      points: [
        [0, 0],
        [end.x - start.x, end.y - start.y],
      ],
      startBinding: {
        elementId: source.id,
        fixedPoint: fixedPointFor(start, sBox).toArray(),
        mode: "orbit",
      },
      endBinding: {
        elementId: target.id,
        fixedPoint: fixedPointFor(end, tBox).toArray(),
        mode: "orbit",
      },
      startArrowhead: null,
      endArrowhead: "arrow",
      elbowed: true,
    };
  }

  /** Parse `text` as a Mermaid flowchart and insert it with top-left at `point`. */
  insertMermaid(text: string, point: Point): boolean {
    const parsed = parseMermaid(text, this.nextSeed());
    if (parsed === null || parsed.length === 0) return false;
    const minX = Math.min(...parsed.map((e) => e.x));
    const minY = Math.min(...parsed.map((e) => e.y));
    const elements = parsed.map((e) => ({
      ...e,
      x: e.x + point.x - minX,
      y: e.y + point.y - minY,
    }));
    this.store.transaction((scene) => {
      for (const el of elements) scene.add(el);
    });
    this.selectedIDs = new Set(elements.map((e) => e.id));
    return true;
  }

  /** Build a `kind` chart for `values` at `point`, grouped and selected. */
  createChart(
    point: Point,
    values: number[],
    labels: string[] = [],
    kind: "bar" | "line" = "bar",
  ): string | null {
    const finite = values.filter((v) => Number.isFinite(v));
    if (finite.length === 0) return null;
    const maxValue = Math.max(Math.max(...finite), 1e-9);
    const barWidth = 44;
    const barGap = 22;
    const step = barWidth + barGap;
    const width = finite.length * step - barGap;
    const height = 200;
    const fill =
      this.currentItem.backgroundColor === "transparent"
        ? "#a5d8ff"
        : this.currentItem.backgroundColor;
    const groupID = this.nextID();

    this.store.transaction((scene) => {
      const axisValues: JSONValue[] = finite.map((v) => v);
      scene.add({
        ...makeBase(this.currentItem, this.nextID(), this.nextSeed(), point.x, point.y + height),
        type: "line",
        width,
        groupIds: [groupID],
        customData: { chart: { kind, values: axisValues, x: point.x, y: point.y } },
        points: [
          [0, 0],
          [width, 0],
        ],
        startBinding: null,
        endBinding: null,
        startArrowhead: null,
        endArrowhead: null,
        polygon: false,
      });

      if (kind === "bar") {
        for (let i = 0; i < finite.length; i++) {
          const barHeight = (finite[i]! / maxValue) * height;
          scene.add({
            ...makeBase(
              this.currentItem,
              this.nextID(),
              this.nextSeed(),
              point.x + i * step,
              point.y + height - barHeight,
            ),
            type: "rectangle",
            width: barWidth,
            height: barHeight,
            backgroundColor: fill,
            fillStyle: "solid",
            groupIds: [groupID],
          });
        }
      } else {
        const points: LocalPoint[] = finite.map((v, i) => [
          i * step + barWidth / 2,
          height - (v / maxValue) * height,
        ]);
        const xs = points.map((p) => p[0]);
        const ys = points.map((p) => p[1]);
        scene.add({
          ...makeBase(this.currentItem, this.nextID(), this.nextSeed(), point.x, point.y),
          type: "line",
          width: Math.max(...xs) - Math.min(...xs),
          height: Math.max(...ys) - Math.min(...ys),
          groupIds: [groupID],
          roundness: { type: RoundnessType.proportionalRadius },
          points,
          startBinding: null,
          endBinding: null,
          startArrowhead: null,
          endArrowhead: null,
          polygon: false,
        });
      }

      labels.forEach((label, i) => {
        if (i >= finite.length || label.length === 0) return;
        scene.add({
          ...makeBase(
            this.currentItem,
            this.nextID(),
            this.nextSeed(),
            point.x + i * step,
            point.y + height + 6,
          ),
          type: "text",
          ...defaultTextProps({
            fontSize: 14,
            text: label,
            originalText: label,
            textAlign: "center",
          }),
          backgroundColor: "transparent",
          groupIds: [groupID],
        });
      });
    });

    const last = [...this.scene.visibleElements]
      .reverse()
      .find((el) => el.groupIds.includes(groupID));
    this.selectedIDs = this.groupSiblings(last?.id ?? "");
    return groupID;
  }

  /** The chart group `id` belongs to, if any (its group contains a chart anchor). */
  chartGroupID(id: string): string | null {
    const el = this.scene.element(id);
    if (el === undefined) return null;
    for (const g of el.groupIds) {
      if (this.scene.visibleElements.some((e) => e.groupIds.includes(g) && hasChartData(e))) {
        return g;
      }
    }
    return null;
  }

  /** The chart's kind/values/origin (from its anchor's `customData`), or null. */
  chartInfo(
    group: string,
  ): { kind: "bar" | "line"; values: number[]; x: number; y: number } | null {
    const anchor = this.scene.visibleElements.find(
      (e) => e.groupIds.includes(group) && hasChartData(e),
    );
    const data = anchor?.customData?.chart as
      | { kind?: unknown; values?: unknown; x?: unknown; y?: unknown }
      | undefined;
    if (data === undefined) return null;
    const values = Array.isArray(data.values)
      ? data.values.filter((v): v is number => typeof v === "number")
      : [];
    return {
      kind: data.kind === "line" ? "line" : "bar",
      values,
      x: typeof data.x === "number" ? data.x : (anchor?.x ?? 0),
      y: typeof data.y === "number" ? data.y : (anchor?.y ?? 0),
    };
  }

  /** The topmost chart hit at `point` (selects its group), or null. */
  chartGroupAt(point: Point): string | null {
    const threshold = this.handleHitRadius("mouse");
    const visible = this.scene.visibleElements;
    for (let k = visible.length - 1; k >= 0; k--) {
      const el = visible[k]!;
      if (!el.locked && hit(el, point, threshold)) {
        const group = this.chartGroupID(el.id);
        if (group !== null) {
          this.selectedIDs = this.groupSiblings(el.id);
          return group;
        }
      }
    }
    return null;
  }

  /** Replace a chart group in place with a new plot kind / data at its origin. */
  updateChart(group: string, kind: "bar" | "line", values: number[]): string | null {
    const info = this.chartInfo(group);
    if (info === null) return null;
    const ids = this.scene.visibleElements
      .filter((e) => e.groupIds.includes(group))
      .map((e) => e.id);
    this.store.modifyScene((scene) => {
      for (const id of ids) scene.remove(id);
    });
    return this.createChart(new Point(info.x, info.y), values, [], kind);
  }
}

function hasChartData(el: ExcalidrawElement): boolean {
  return el.customData?.chart !== undefined;
}

function boxOf(a: Point, b: Point): BoundingBox {
  return new BoundingBox(
    Math.min(a.x, b.x),
    Math.min(a.y, b.y),
    Math.max(a.x, b.x),
    Math.max(a.y, b.y),
  );
}

function roundnessType(type: string): number | null {
  if (type === "line" || type === "arrow") return RoundnessType.proportionalRadius;
  if (type === "rectangle" || type === "diamond") return RoundnessType.adaptiveRadius;
  return null;
}

/** The relative points of a line/arrow, or null for other element types. */
function linearPointsOf(el: ExcalidrawElement): LocalPoint[] | null {
  return el.type === "line" || el.type === "arrow" ? el.points : null;
}

/** Replace a line/arrow's points, recomputing its width/height. */
function setLinearPoints(points: LocalPoint[], el: ExcalidrawElement): ExcalidrawElement {
  if (el.type !== "line" && el.type !== "arrow") return el;
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  return {
    ...el,
    points,
    width: (xs.length === 0 ? 0 : Math.max(...xs)) - (xs.length === 0 ? 0 : Math.min(...xs)),
    height: (ys.length === 0 ? 0 : Math.max(...ys)) - (ys.length === 0 ? 0 : Math.min(...ys)),
  };
}

/** Register `arrowID` in `targetID`'s boundElements (no duplicates). */
function addBoundArrow(scene: Scene, arrowID: string, targetID: string): void {
  const target = scene.element(targetID);
  if (target === undefined) return;
  const bound = target.boundElements ?? [];
  if (bound.some((b) => b.id === arrowID)) return;
  scene.replace({ ...target, boundElements: [...bound, { id: arrowID, type: "arrow" }] });
}

/**
 * Recompute the endpoints of bound arrows from their targets' current bounds,
 * skipping arrows that are themselves being dragged. Elbow routing is applied
 * straight for now (the elbow router is a later slice). (parity: updateBoundArrows)
 */
function updateBoundArrows(scene: Scene, skipping: Set<string>): void {
  for (const element of scene.elements) {
    if (element.isDeleted || skipping.has(element.id) || element.type !== "arrow") continue;
    if (element.startBinding === null && element.endBinding === null) continue;
    const first = element.points[0];
    const last = element.points[element.points.length - 1];
    if (first === undefined || last === undefined) continue;
    let startGlobal = new Point(element.x + first[0], element.y + first[1]);
    let endGlobal = new Point(element.x + last[0], element.y + last[1]);
    if (element.startBinding !== null) {
      const target = scene.element(element.startBinding.elementId);
      if (target !== undefined) {
        startGlobal = pointForFixedPoint(
          Point.fromArray(element.startBinding.fixedPoint),
          elementBounds(target),
        );
      }
    }
    if (element.endBinding !== null) {
      const target = scene.element(element.endBinding.elementId);
      if (target !== undefined) {
        endGlobal = pointForFixedPoint(
          Point.fromArray(element.endBinding.fixedPoint),
          elementBounds(target),
        );
      }
    }
    if (element.elbowed) {
      scene.replace(applyElbowRoute(scene, element, startGlobal, endGlobal));
    } else {
      scene.replace({
        ...element,
        x: startGlobal.x,
        y: startGlobal.y,
        width: Math.abs(endGlobal.x - startGlobal.x),
        height: Math.abs(endGlobal.y - startGlobal.y),
        points: [
          [0, 0],
          [endGlobal.x - startGlobal.x, endGlobal.y - startGlobal.y],
        ],
      });
    }
  }
}

/** Bounds of the element with `id`, or null. */
function boundsOfId(scene: Scene, id: string): BoundingBox | null {
  const el = scene.element(id);
  return el === undefined ? null : elementBounds(el);
}

/**
 * Rewrite an arrow's points as the elbow route between two global endpoints,
 * re-anchoring its origin/size. No-op for non-elbow arrows. (parity: applyElbowRoute)
 */
function applyElbowRoute(
  scene: Scene,
  arrow: ArrowElement,
  startGlobal: Point,
  endGlobal: Point,
): ArrowElement {
  if (!arrow.elbowed) return arrow;
  const fixed = arrow.fixedSegments;
  let routed: Point[];
  if (fixed !== undefined && fixed.length > 0 && arrow.points.length >= 4) {
    const global = arrow.points.map((p) => new Point(arrow.x + p[0], arrow.y + p[1]));
    routed = ElbowArrow.followEndpoints(global, startGlobal, endGlobal);
  } else {
    const startBox =
      arrow.startBinding !== null ? boundsOfId(scene, arrow.startBinding.elementId) : null;
    const endBox = arrow.endBinding !== null ? boundsOfId(scene, arrow.endBinding.elementId) : null;
    routed = ElbowArrow.route(startGlobal, startBox, endGlobal, endBox);
  }
  const origin = routed[0] ?? startGlobal;
  const points: LocalPoint[] = routed.map((p) => [p.x - origin.x, p.y - origin.y]);
  let fixedSegments = arrow.fixedSegments;
  if (fixedSegments !== undefined && fixedSegments.length > 0) {
    fixedSegments = fixedSegments.flatMap((seg) =>
      seg.index < 0 || seg.index >= points.length
        ? []
        : [{ start: points[seg.index - 1]!, end: points[seg.index]!, index: seg.index }],
    );
  }
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  return {
    ...arrow,
    points,
    x: origin.x,
    y: origin.y,
    width: Math.max(...xs) - Math.min(...xs),
    height: Math.max(...ys) - Math.min(...ys),
    fixedSegments,
  };
}

function edgePoint(box: BoundingBox, heading: FlowchartDirection): Point {
  const midX = (box.minX + box.maxX) / 2;
  const midY = (box.minY + box.maxY) / 2;
  switch (heading) {
    case "up":
      return new Point(midX, box.minY);
    case "down":
      return new Point(midX, box.maxY);
    case "left":
      return new Point(box.minX, midY);
    case "right":
      return new Point(box.maxX, midY);
  }
}

function isLinearElement(el: ExcalidrawElement): boolean {
  return el.type === "arrow" || el.type === "line" || el.type === "freedraw";
}

/** Extract just the base properties of an element (dropping type-specific fields). */
function baseOf(el: ExcalidrawElement): BaseProperties {
  const base: BaseProperties = {
    id: el.id,
    x: el.x,
    y: el.y,
    width: el.width,
    height: el.height,
    angle: el.angle,
    strokeColor: el.strokeColor,
    backgroundColor: el.backgroundColor,
    fillStyle: el.fillStyle,
    strokeWidth: el.strokeWidth,
    strokeStyle: el.strokeStyle,
    roundness: el.roundness,
    roughness: el.roughness,
    opacity: el.opacity,
    seed: el.seed,
    version: el.version,
    versionNonce: el.versionNonce,
    index: el.index,
    isDeleted: el.isDeleted,
    groupIds: el.groupIds,
    frameId: el.frameId,
    boundElements: el.boundElements,
    updated: el.updated,
    link: el.link,
    locked: el.locked,
  };
  if (el.customData !== undefined) base.customData = el.customData;
  return base;
}

/** Build a line element from absolute `vertices`, normalized to its own origin. */
function polylineElement(
  base: BaseProperties,
  vertices: Point[],
  polygon: boolean,
): ExcalidrawElement {
  const origin = vertices[0] ?? Point.zero;
  const local: LocalPoint[] = vertices.map((v) => [v.x - origin.x, v.y - origin.y]);
  const xs = local.map((p) => p[0]);
  const ys = local.map((p) => p[1]);
  return {
    ...base,
    x: origin.x,
    y: origin.y,
    width: Math.max(...xs) - Math.min(...xs),
    height: Math.max(...ys) - Math.min(...ys),
    type: "line",
    points: local,
    startBinding: null,
    endBinding: null,
    startArrowhead: null,
    endArrowhead: null,
    polygon,
  };
}

function isSuperset(set: Set<string>, subset: Set<string>): boolean {
  for (const id of subset) if (!set.has(id)) return false;
  return true;
}

function flipPoints(el: ExcalidrawElement, horizontal: boolean): void {
  if (el.type !== "line" && el.type !== "arrow" && el.type !== "freedraw") return;
  const xs = el.points.map((p) => p[0]);
  const ys = el.points.map((p) => p[1]);
  const maxX = Math.max(...xs);
  const maxY = Math.max(...ys);
  el.points = el.points.map((p) => [
    horizontal ? maxX - p[0] : p[0],
    horizontal ? p[1] : maxY - p[1],
  ]);
}
