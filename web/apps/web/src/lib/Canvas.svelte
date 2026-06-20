<script lang="ts">
  import { Point } from "@cyberdynecorp/excalidraw-svelte/math";
  import type { EditorStore } from "@cyberdynecorp/excalidraw-svelte";
  import type { PointerType } from "@cyberdynecorp/excalidraw-svelte/editor";

  let { store, rev }: { store: EditorStore; rev: number } = $props();

  let canvas: HTMLCanvasElement;
  let wrapper: HTMLDivElement;
  let width = $state(800);
  let height = $state(600);
  let down = false;
  // Middle-mouse panning: while held, pointer moves pan the canvas instead of
  // drawing/selecting. Tracks the last client position to derive the delta.
  let panning = false;
  let lastPanX = 0;
  let lastPanY = 0;

  // Bitmap cache for image elements: the pure renderer delegates image drawing
  // to the host (it can't load bitmaps synchronously). Load each file's dataURL
  // once and redraw when it's ready; until then the image is skipped that frame.
  const imageCache = new Map<string, HTMLImageElement>();
  function imageFor(fileId: string): CanvasImageSource | null {
    const cached = imageCache.get(fileId);
    if (cached !== undefined) return cached.complete && cached.naturalWidth > 0 ? cached : null;
    const file = store.scene.files[fileId];
    if (file === undefined) return null;
    const img = new Image();
    img.onload = () => draw();
    img.src = file.dataURL;
    imageCache.set(fileId, img);
    return null; // not decoded yet; onload triggers a redraw
  }

  function draw(): void {
    if (canvas === undefined) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    const ctx = canvas.getContext("2d");
    if (ctx === null) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const rc = ctx as unknown as Parameters<EditorStore["render"]>[0];
    store.render(rc, width, height, imageFor);
    store.renderOverlay(rc, width, height);
  }

  // Redraw whenever the scene revision (via `rev`), theme, or size changes.
  $effect(() => {
    void rev;
    void width;
    void height;
    draw();
  });

  // Animate the fading laser/eraser trails while one is active.
  $effect(() => {
    void rev;
    if (store.activeTool !== "laser" && store.activeTool !== "eraser") return;
    let raf = 0;
    const tick = (): void => {
      draw();
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  });

  $effect(() => {
    const ro = new ResizeObserver((entries) => {
      const r = entries[0]?.contentRect;
      if (r !== undefined) {
        width = r.width;
        height = r.height;
      }
    });
    ro.observe(wrapper);
    return () => ro.disconnect();
  });

  function toScene(e: PointerEvent): Point {
    const r = canvas.getBoundingClientRect();
    return new Point(e.clientX - r.left, e.clientY - r.top);
  }

  function opts(e: PointerEvent) {
    return {
      type: (e.pointerType === "pen" ? "pen" : e.pointerType === "touch" ? "touch" : "mouse") as PointerType,
      pressure: e.pressure || 0.5,
      shift: e.shiftKey,
      alt: e.altKey,
      toggle: e.metaKey || e.ctrlKey,
    };
  }

  function onPointerDown(e: PointerEvent): void {
    // Middle button grabs the canvas to pan, regardless of the active tool.
    if (e.button === 1) {
      e.preventDefault();
      panning = true;
      lastPanX = e.clientX;
      lastPanY = e.clientY;
      canvas.setPointerCapture(e.pointerId);
      return;
    }
    // The right button is reserved for the context menu — never let it draw or
    // change the selection (otherwise right-clicking empty space deselects).
    if (e.button === 2) return;
    down = true;
    canvas.setPointerCapture(e.pointerId);
    store.pointer("down", toScene(e), opts(e));
  }
  function onPointerMove(e: PointerEvent): void {
    if (panning) {
      store.panZoom(e.clientX - lastPanX, e.clientY - lastPanY, 1);
      lastPanX = e.clientX;
      lastPanY = e.clientY;
      return;
    }
    store.trackPointer(toScene(e)); // broadcast cursor for presence (no-op when solo)
    if (!down) return;
    store.pointer("move", toScene(e), opts(e));
  }
  function onPointerUp(e: PointerEvent): void {
    if (panning) {
      panning = false;
      canvas.releasePointerCapture(e.pointerId);
      return;
    }
    if (!down) return;
    down = false;
    store.pointer("up", toScene(e), opts(e));
  }

  function onDblClick(e: MouseEvent): void {
    const r = canvas.getBoundingClientRect();
    store.doubleClickAt(new Point(e.clientX - r.left, e.clientY - r.top));
  }

  function onWheel(e: WheelEvent): void {
    e.preventDefault();
    const r = canvas.getBoundingClientRect();
    // Shift+wheel pans horizontally (handy on a plain wheel mouse); otherwise
    // the wheel zooms in/out around the cursor.
    if (e.shiftKey && !e.ctrlKey && !e.metaKey) {
      store.panZoom(-(e.deltaY || e.deltaX), 0, 1);
      return;
    }
    store.zoomAtScreenPoint(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.1 : 1 / 1.1);
  }
</script>

<div bind:this={wrapper} class="canvas-wrap">
  <canvas
    bind:this={canvas}
    data-testid="canvas"
    style="width:{width}px;height:{height}px"
    onpointerdown={onPointerDown}
    onpointermove={onPointerMove}
    onpointerup={onPointerUp}
    onpointercancel={onPointerUp}
    ondblclick={onDblClick}
    onwheel={onWheel}
  ></canvas>
</div>

<style>
  .canvas-wrap { position: absolute; inset: 0; }
  canvas { display: block; touch-action: none; }
</style>
