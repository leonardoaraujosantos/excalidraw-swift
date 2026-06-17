<script lang="ts">
  import type { Tool } from "@xs/editor";
  import { EditorStore } from "@xs/svelte";
  import Canvas from "./lib/Canvas.svelte";

  const store = new EditorStore();
  // Re-read reactive bits by touching `revision`.
  let rev = $state(0);
  $effect(() => {
    const id = setInterval(() => {
      rev = store.revision;
    }, 60);
    return () => clearInterval(id);
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
    { tool: "eraser", label: "⌫ Erase" },
    { tool: "hand", label: "✋ Hand" },
  ];

  let strokeColor = $state("#1e1e1e");
  let backgroundColor = $state("transparent");
  let strokeWidth = $state(2);
  let elbowed = $state(false);

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
</script>

<div class="app" data-theme={store.theme} data-rev={rev}>
  <header class="toolbar">
    {#each tools as t (t.tool)}
      <button class:active={store.activeTool === t.tool} onclick={() => pick(t.tool)}>{t.label}</button>
    {/each}
    <span class="sep"></span>
    <button onclick={() => store.insertStickyNote()}>Note</button>
    <button onclick={() => store.insertTable()}>Table</button>
    <button onclick={() => store.insertChart([10, 20, 15, 30])}>Chart</button>
    <button onclick={() => store.insertMermaid(mermaidSample)}>Mermaid</button>
  </header>

  <section class="props">
    <label>Stroke <input type="color" bind:value={strokeColor} onchange={() => store.setStrokeColor(strokeColor)} /></label>
    <label>Fill <input type="color" bind:value={backgroundColor} onchange={() => store.setBackgroundColor(backgroundColor)} /></label>
    <label>Width
      <input type="range" min="1" max="12" bind:value={strokeWidth} onchange={() => store.setStrokeWidth(strokeWidth)} />
    </label>
    <label><input type="checkbox" bind:checked={elbowed} onchange={() => store.setElbowed(elbowed)} /> Elbow</label>
    <span class="sep"></span>
    <button onclick={() => store.undo()} disabled={!store.canUndo}>Undo</button>
    <button onclick={() => store.redo()} disabled={!store.canRedo}>Redo</button>
    <button onclick={() => store.deleteSelected()}>Delete</button>
    <button onclick={() => store.duplicate()}>Duplicate</button>
    <button onclick={() => store.group()}>Group</button>
  </section>

  <main class="stage">
    <Canvas {store} />
  </main>

  <footer class="status">
    <button onclick={() => store.zoomOut()}>−</button>
    <button onclick={() => store.resetZoom()}>{store.zoomPercent}%</button>
    <button onclick={() => store.zoomIn()}>+</button>
    <span class="sep"></span>
    <span>{store.selectionStats ?? ""}</span>
    <span class="grow"></span>
    <button onclick={() => store.toggleTheme()}>{store.theme === "light" ? "🌙" : "☀️"}</button>
    <button onclick={downloadSvg}>Export SVG</button>
    <button onclick={downloadJson}>Save</button>
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
  .sep { width: 1px; align-self: stretch; background: #0002; margin: 0 4px; }
  .grow { flex: 1; }
  label { display: inline-flex; gap: 4px; align-items: center; font-size: 13px; }
</style>
