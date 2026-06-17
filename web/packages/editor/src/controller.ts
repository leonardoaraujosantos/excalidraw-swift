import {
  BoundingBox,
  DEFAULT_SNAP_DISTANCE,
  type RecognizedShape,
  type ShapeRecognition,
  ShapeRecognizer,
  commonBounds,
  bounds as elementBounds,
  frameChildren,
  frameContaining,
  gapSnap,
  hit,
  isFrame,
  snap as objectSnap,
} from "@xs/geometry";
import { Point } from "@xs/math";
import {
  type BaseProperties,
  type BinaryFileData,
  type ExcalidrawElement,
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
} from "@xs/model";
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
  | { kind: "resizing"; handle: TransformHandle; bounds: BoundingBox; originals: Originals }
  | { kind: "rotating"; center: Point; originals: Originals };

export type ZOrder = "front" | "back" | "forward" | "backward";
export type Alignment = "left" | "centerX" | "right" | "top" | "centerY" | "bottom";

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

  private interaction: Interaction = { kind: "idle" };
  private readonly nextID: () => string;
  private readonly nextSeed: () => number;

  constructor(scene: Scene = new Scene(), idProvider?: () => string, seedProvider?: () => number) {
    this.store = new Store(scene);
    let idCounter = 0;
    let seedCounter = 1;
    this.nextID = idProvider ?? (() => `el-${++idCounter}`);
    this.nextSeed = seedProvider ?? (() => ++seedCounter * 100_001);
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
    if (this.activeTool !== "selection" || bounds === null) return new Map();
    return Transform.handlePositions(bounds, this.rotationOffset);
  }

  // MARK: Pointer handling

  pointerDown(e: PointerEvent): void {
    this.selectionRect = null;
    if (this.activeTool === "eraser") {
      this.interaction = { kind: "erasing" };
      this.eraseAt(e.scenePoint);
      return;
    }
    if (this.activeTool === "hand") return;
    const type = toolElementType(this.activeTool);
    if (type !== null) this.beginCreating(type, e.scenePoint, e.pressure);
    else this.beginSelectionInteraction(e);
  }

  pointerMove(e: PointerEvent): void {
    const i = this.interaction;
    switch (i.kind) {
      case "creating":
        this.updateCreating(i.id, i.origin, e.scenePoint);
        this.interaction = { ...i, moved: true };
        break;
      case "freehand":
        this.appendFreehandPoint(i.id, i.origin, e.scenePoint, e.pressure);
        break;
      case "erasing":
        this.eraseAt(e.scenePoint);
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
    const i = this.interaction;
    switch (i.kind) {
      case "creating":
        this.finishCreating(i.id, i.moved);
        break;
      case "freehand":
        this.finishFreehand();
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
    this.selectedIDs = new Set();
    this.interaction = { kind: "idle" };
  }

  setTool(tool: Tool): void {
    this.activeTool = tool;
  }

  selectAll(): void {
    this.selectedIDs = new Set(this.scene.visibleElements.map((el) => el.id));
  }

  clearSelection(): void {
    this.selectedIDs = new Set();
  }

  deleteSelected(): void {
    if (this.selectedIDs.size === 0) return;
    this.store.transaction((scene) => {
      for (const id of this.selectedIDs) scene.remove(id);
    });
    this.selectedIDs = new Set();
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
      this.reassignFrameMembership(new Set([id]));
      this.store.commit();
      if (!this.toolLocked) this.activeTool = "selection";
    }
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

  private eraseAt(point: Point): void {
    const threshold = this.handleHitRadius("mouse");
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
    for (const el of this.selectedElements) {
      if (isFrame(el)) {
        for (const child of frameChildren(el.id, this.scene.visibleElements)) {
          result.set(child.id, child);
        }
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
        width: Math.max(0, ...lines.map((l) => l.length)) * el.fontSize * 0.6,
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
        draft.width = Math.max(0, ...lines.map((l) => l.length)) * draft.fontSize * 0.6;
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
        customData: { chart: { kind, values: axisValues } },
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
