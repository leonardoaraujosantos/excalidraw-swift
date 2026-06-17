<script lang="ts">
  import { Point } from "@xs/math";
  import type { EditorStore } from "@xs/svelte";
  import type { PointerType } from "@xs/editor";

  let { store }: { store: EditorStore } = $props();

  let canvas: HTMLCanvasElement;
  let wrapper: HTMLDivElement;
  let width = $state(800);
  let height = $state(600);
  let down = false;

  function draw(): void {
    if (canvas === undefined) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    const ctx = canvas.getContext("2d");
    if (ctx === null) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    store.render(ctx as unknown as Parameters<EditorStore["render"]>[0], width, height);
  }

  // Redraw whenever the scene revision, theme, or size changes.
  $effect(() => {
    void store.revision;
    void store.theme;
    void width;
    void height;
    draw();
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
    down = true;
    canvas.setPointerCapture(e.pointerId);
    store.pointer("down", toScene(e), opts(e));
  }
  function onPointerMove(e: PointerEvent): void {
    if (!down) return;
    store.pointer("move", toScene(e), opts(e));
  }
  function onPointerUp(e: PointerEvent): void {
    if (!down) return;
    down = false;
    store.pointer("up", toScene(e), opts(e));
  }

  function onWheel(e: WheelEvent): void {
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) {
      store.panZoom(0, 0, e.deltaY < 0 ? 1.1 : 1 / 1.1);
    } else {
      store.panZoom(-e.deltaX, -e.deltaY, 1);
    }
  }
</script>

<div bind:this={wrapper} class="canvas-wrap">
  <canvas
    bind:this={canvas}
    style="width:{width}px;height:{height}px"
    onpointerdown={onPointerDown}
    onpointermove={onPointerMove}
    onpointerup={onPointerUp}
    onpointercancel={onPointerUp}
    onwheel={onWheel}
  ></canvas>
</div>

<style>
  .canvas-wrap { position: absolute; inset: 0; }
  canvas { display: block; touch-action: none; }
</style>
