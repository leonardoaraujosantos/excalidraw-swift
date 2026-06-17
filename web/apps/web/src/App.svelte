<script lang="ts">
  import type { Tool } from "@xs/editor";
  import type { FillStyle } from "@xs/model";
  import { EditorStore } from "@xs/svelte";
  import Canvas from "./lib/Canvas.svelte";

  const store = new EditorStore();
  // Expose the store for end-to-end tests to assert against the scene.
  (window as unknown as { __store?: EditorStore }).__store = store;
  // The store is plain TS, so its reads aren't reactive on their own. Poll the
  // revision counter and expose store-derived UI state through `view`, which
  // re-derives whenever `rev` changes (fine-grained reactivity in runes mode).
  let rev = $state(0);
  $effect(() => {
    const id = setInterval(() => {
      rev = store.revision;
    }, 40);
    return () => clearInterval(id);
  });
  const view = $derived.by(() => {
    void rev;
    return {
      tool: store.activeTool,
      canUndo: store.canUndo,
      canRedo: store.canRedo,
      zoom: store.zoomPercent,
      theme: store.theme,
      stats: store.selectionStats,
      editing: store.editingText,
    };
  });

  const tools: { tool: Tool; label: string }[] = [
    { tool: "selection", label: "▢ Select" },
    { tool: "rectangle", label: "▭ Rect" },
    { tool: "diamond", label: "◇ Diamond" },
    { tool: "ellipse", label: "◯ Ellipse" },
    { tool: "arrow", label: "→ Arrow" },
    { tool: "line", label: "／ Line" },
    { tool: "freedraw", label: "✎ Draw" },
    { tool: "text", label: "T Text" },
    { tool: "frame", label: "⛶ Frame" },
    { tool: "laser", label: "⦿ Laser" },
    { tool: "eraser", label: "⌫ Erase" },
    { tool: "hand", label: "✋ Hand" },
  ];

  let fileInput: HTMLInputElement;

  function importImage(e: Event): void {
    const file = (e.currentTarget as HTMLInputElement).files?.[0];
    if (file === undefined) return;
    const reader = new FileReader();
    reader.onload = () => {
      const dataURL = reader.result as string;
      const img = new Image();
      img.onload = () => store.insertImage(dataURL, file.type, img.naturalWidth, img.naturalHeight);
      img.src = dataURL;
    };
    reader.readAsDataURL(file);
  }

  let strokeColor = $state("#1e1e1e");
  let backgroundColor = $state("transparent");
  let strokeWidth = $state(2);
  let elbowed = $state(false);
  let fillStyle = $state<FillStyle>("hachure");

  function pick(tool: Tool): void {
    store.selectTool(tool);
  }

  function downloadSvg(): void {
    const blob = new Blob([store.exportSvg()], { type: "image/svg+xml" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "drawing.svg";
    a.click();
  }

  function downloadJson(): void {
    const blob = new Blob([store.documentJSON()], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "drawing.excalidraw";
    a.click();
  }

  const mermaidSample = "flowchart TD\n  A[Start] --> B{OK?}\n  B -->|Yes| C[Ship]\n  B -->|No| D[Fix]";

  const toolKeys: Record<string, Tool> = {
    v: "selection",
    r: "rectangle",
    d: "diamond",
    o: "ellipse",
    a: "arrow",
    l: "line",
    p: "freedraw",
    t: "text",
    e: "eraser",
    h: "hand",
    f: "frame",
  };

  function onKeydown(e: KeyboardEvent): void {
    if (store.editingText !== null) return;
    const target = e.target as HTMLElement | null;
    if (target !== null && (target.tagName === "INPUT" || target.tagName === "TEXTAREA")) return;
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === "z") {
      e.preventDefault();
      if (e.shiftKey) store.redo();
      else store.undo();
      return;
    }
    if (mod && e.key.toLowerCase() === "d") {
      e.preventDefault();
      store.duplicate();
      return;
    }
    if (mod && e.key.toLowerCase() === "a") {
      e.preventDefault();
      store.selectAll();
      return;
    }
    if (e.key === "Backspace" || e.key === "Delete") {
      store.deleteSelected();
      return;
    }
    const tool = toolKeys[e.key.toLowerCase()];
    if (tool !== undefined) store.selectTool(tool);
  }
</script>

<svelte:window onkeydown={onKeydown} />

<div class="app" data-theme={view.theme} data-rev={rev}>
  <header class="toolbar">
    {#each tools as t (t.tool)}
      <button data-testid={`tool-${t.tool}`} class:active={view.tool === t.tool} onclick={() => pick(t.tool)}>{t.label}</button>
    {/each}
    <span class="sep"></span>
    <button data-testid="gen-note" onclick={() => store.insertStickyNote()}>Note</button>
    <button data-testid="gen-table" onclick={() => store.insertTable()}>Table</button>
    <button data-testid="gen-chart" onclick={() => store.insertChart([10, 20, 15, 30])}>Chart</button>
    <button data-testid="gen-mermaid" onclick={() => store.insertMermaid(mermaidSample)}>Mermaid</button>
    <button data-testid="gen-image" onclick={() => fileInput.click()}>Image</button>
    <input bind:this={fileInput} type="file" accept="image/*" hidden onchange={importImage} />
  </header>

  <section class="props">
    <label>Stroke <input type="color" bind:value={strokeColor} onchange={() => store.setStrokeColor(strokeColor)} /></label>
    <label>Fill <input type="color" bind:value={backgroundColor} onchange={() => store.setBackgroundColor(backgroundColor)} /></label>
    <label>Pattern
      <select data-testid="fill-style" bind:value={fillStyle} onchange={() => store.setFillStyle(fillStyle)}>
        <option value="hachure">Hachure</option>
        <option value="cross-hatch">Cross-hatch</option>
        <option value="solid">Solid</option>
        <option value="zigzag">Zigzag</option>
      </select>
    </label>
    <label>Width
      <input type="range" min="1" max="12" bind:value={strokeWidth} onchange={() => store.setStrokeWidth(strokeWidth)} />
    </label>
    <label><input type="checkbox" bind:checked={elbowed} onchange={() => store.setElbowed(elbowed)} /> Elbow</label>
    <span class="sep"></span>
    <button data-testid="undo" onclick={() => store.undo()} disabled={!view.canUndo}>Undo</button>
    <button data-testid="redo" onclick={() => store.redo()} disabled={!view.canRedo}>Redo</button>
    <button data-testid="delete" onclick={() => store.deleteSelected()}>Delete</button>
    <button data-testid="duplicate" onclick={() => store.duplicate()}>Duplicate</button>
    <button data-testid="group" onclick={() => store.group()}>Group</button>
    <button onclick={() => store.ungroup()}>Ungroup</button>
    <span class="sep"></span>
    <button title="Align left" onclick={() => store.align("left")}>⇤</button>
    <button title="Align centre" onclick={() => store.align("centerX")}>↔</button>
    <button title="Align right" onclick={() => store.align("right")}>⇥</button>
    <button title="Flip horizontal" onclick={() => store.flip(true)}>⇋</button>
    <button title="Bring to front" onclick={() => store.reorder("front")}>⤒</button>
    <button title="Send to back" onclick={() => store.reorder("back")}>⤓</button>
  </section>

  <main class="stage">
    <Canvas {store} {rev} />
    {#if view.editing !== null}
      <!-- svelte-ignore a11y_autofocus -->
      <textarea
        class="text-editor"
        data-testid="text-editor"
        autofocus
        style="left:{view.editing.viewX}px;top:{view.editing.viewY}px"
        value={view.editing.value}
        oninput={(e) => store.setEditingText((e.currentTarget as HTMLTextAreaElement).value)}
        onblur={() => store.commitText()}
        onkeydown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            store.commitText();
          }
        }}
      ></textarea>
    {/if}
  </main>

  <footer class="status">
    <button data-testid="zoom-out" onclick={() => store.zoomOut()}>−</button>
    <button data-testid="zoom-reset" onclick={() => store.resetZoom()}>{view.zoom}%</button>
    <button data-testid="zoom-in" onclick={() => store.zoomIn()}>+</button>
    <span class="sep"></span>
    <span data-testid="selection-stats">{view.stats ?? ""}</span>
    <span class="grow"></span>
    <button data-testid="theme" onclick={() => store.toggleTheme()}>{view.theme === "light" ? "🌙" : "☀️"}</button>
    <button data-testid="export-svg" onclick={downloadSvg}>Export SVG</button>
    <button data-testid="save" onclick={downloadJson}>Save</button>
  </footer>
</div>

<style>
  .app { position: absolute; inset: 0; display: grid; grid-template-rows: auto auto 1fr auto; }
  .app[data-theme="dark"] { background: #121212; color: #eee; }
  .toolbar, .props, .status { display: flex; gap: 6px; align-items: center; padding: 6px 10px; border-bottom: 1px solid #0002; flex-wrap: wrap; }
  .status { border-top: 1px solid #0002; border-bottom: none; }
  button { padding: 4px 8px; border: 1px solid #0003; border-radius: 6px; background: #fff; cursor: pointer; }
  .app[data-theme="dark"] button { background: #2a2a2a; color: #eee; border-color: #fff3; }
  button.active { background: #4263eb; color: #fff; border-color: #4263eb; }
  .stage { position: relative; }
  .text-editor {
    position: absolute;
    min-width: 120px;
    min-height: 28px;
    font: 20px system-ui, sans-serif;
    border: 1px dashed #4263eb;
    background: transparent;
    resize: none;
    outline: none;
    padding: 0;
  }
  .sep { width: 1px; align-self: stretch; background: #0002; margin: 0 4px; }
  .grow { flex: 1; }
  label { display: inline-flex; gap: 4px; align-items: center; font-size: 13px; }
</style>
