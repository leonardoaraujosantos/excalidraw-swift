<script lang="ts">
  import type { Tool } from "@cyberdynecorp/excalidraw-svelte/editor";
  import type { FillStyle } from "@cyberdynecorp/excalidraw-svelte/model";
  import { EditorStore, browserSocket, reconnectingSocket } from "@cyberdynecorp/excalidraw-svelte";
  import { YjsCollab, type AwarenessLike } from "@cyberdynecorp/excalidraw-yjs";
  import { Awareness } from "y-protocols/awareness";
  import * as Y from "yjs";
  import Canvas from "./lib/Canvas.svelte";
  import { BroadcastChannelProvider } from "./lib/yjs-broadcast-provider";

  const store = new EditorStore();
  // Expose the store for end-to-end tests to assert against the scene.
  (window as unknown as { __store?: EditorStore }).__store = store;

  // Auto-join a collaboration room from the URL: ?relay=ws://…&room=…&name=…
  const params = new URLSearchParams(location.search);
  const relayUrl = params.get("relay");
  const roomName = params.get("room");
  if (relayUrl !== null && roomName !== null) {
    const palette = ["#e64980", "#4263eb", "#0ca678", "#f08c00", "#ae3ec9"];
    const peer = {
      id: `web-${Math.random().toString(36).slice(2, 8)}`,
      name: params.get("name") ?? "Guest",
      color: palette[Math.floor(Math.random() * palette.length)]!,
    };
    store.startCollab(reconnectingSocket(() => browserSocket(relayUrl)), peer, roomName);
  }

  // Or join a Yjs/CRDT room from the URL: ?yjs=<room> (same-origin BroadcastChannel
  // provider; the adapter itself works with any provider). Exposed for E2E tests.
  const yjsRoom = params.get("yjs");
  if (yjsRoom !== null) {
    const palette = ["#e64980", "#4263eb", "#0ca678", "#f08c00", "#ae3ec9"];
    const peer = {
      id: `web-${Math.random().toString(36).slice(2, 8)}`,
      name: params.get("name") ?? "Guest",
      color: palette[Math.floor(Math.random() * palette.length)]!,
    };
    const ydoc = new Y.Doc();
    const awareness = new Awareness(ydoc);
    const provider = new BroadcastChannelProvider(ydoc, yjsRoom, awareness);
    const collab = new YjsCollab(store, ydoc, {
      awareness: awareness as unknown as AwarenessLike,
      peer,
    });
    collab.start();
    (window as unknown as { __yjs?: unknown }).__yjs = { doc: ydoc, collab, provider, awareness };
  }
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
      table: store.selectedTableGroup,
      chart: store.editingChart,
      peers: store.collab === null ? [] : [...store.collab.peers.values()],
      selectedCount: store.selectedCount,
      canGroup: store.canGroupSelection,
      canUngroup: store.canUngroupSelection,
    };
  });

  // Right-click context menu over the canvas (scene coords not needed: it acts
  // on the current selection). `null` when hidden.
  let menu = $state<{ x: number; y: number } | null>(null);
  function openMenu(e: MouseEvent): void {
    e.preventDefault();
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    menu = { x: e.clientX - r.left, y: e.clientY - r.top };
  }
  function closeMenu(): void {
    menu = null;
  }
  function runMenu(action: () => void): void {
    action();
    closeMenu();
  }

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
    if (e.key === "Escape" && menu !== null) {
      closeMenu();
      return;
    }
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
    {#if view.table !== null}
      <span class="sep"></span>
      <button data-testid="table-add-row" onclick={() => store.addTableRow()}>+ Row</button>
      <button data-testid="table-add-col" onclick={() => store.addTableColumn()}>+ Col</button>
    {/if}
    <span class="sep"></span>
    <button title="Align left" onclick={() => store.align("left")}>⇤</button>
    <button title="Align centre" onclick={() => store.align("centerX")}>↔</button>
    <button title="Align right" onclick={() => store.align("right")}>⇥</button>
    <button title="Flip horizontal" onclick={() => store.flip(true)}>⇋</button>
    <button title="Bring to front" onclick={() => store.reorder("front")}>⤒</button>
    <button title="Send to back" onclick={() => store.reorder("back")}>⤓</button>
  </section>

  <main class="stage" oncontextmenu={openMenu}>
    <Canvas {store} {rev} />
    {#if view.editing !== null}
      <!-- svelte-ignore a11y_autofocus -->
      <textarea
        class="text-editor"
        data-testid="text-editor"
        autofocus
        style="left:{view.editing.viewX}px;top:{view.editing.viewY}px{view.editing.viewW
          ? `;width:${view.editing.viewW}px;min-width:0;height:${view.editing.viewH}px`
          : ''}"
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
    {#if view.chart !== null}
      <div class="chart-editor" data-testid="chart-editor" style="left:{view.chart.viewX}px;top:{view.chart.viewY}px">
        <label>Plot
          <select
            data-testid="chart-kind"
            value={view.chart.kind}
            onchange={(e) => store.setChartKind((e.currentTarget as HTMLSelectElement).value as "bar" | "line")}
          >
            <option value="bar">Bar</option>
            <option value="line">Line</option>
          </select>
        </label>
        <label>Data
          <input
            data-testid="chart-data"
            type="text"
            value={view.chart.values}
            oninput={(e) => store.setChartValues((e.currentTarget as HTMLInputElement).value)}
          />
        </label>
        <button data-testid="chart-apply" onclick={() => store.commitChart()}>Apply</button>
        <button onclick={() => store.cancelChart()}>Cancel</button>
      </div>
    {/if}
    {#if menu !== null}
      <button
        type="button"
        class="ctx-backdrop"
        aria-label="Dismiss menu"
        onclick={closeMenu}
        oncontextmenu={(e) => {
          e.preventDefault();
          closeMenu();
        }}
      ></button>
      <div class="context-menu" data-testid="context-menu" style="left:{menu.x}px;top:{menu.y}px">
        <button data-testid="ctx-duplicate" disabled={view.selectedCount === 0} onclick={() => runMenu(() => store.duplicate())}>Duplicate</button>
        <button data-testid="ctx-group" disabled={!view.canGroup} onclick={() => runMenu(() => store.group())}>Group</button>
        <button data-testid="ctx-ungroup" disabled={!view.canUngroup} onclick={() => runMenu(() => store.ungroup())}>Ungroup</button>
        <div class="ctx-sep"></div>
        <button data-testid="ctx-front" disabled={view.selectedCount === 0} onclick={() => runMenu(() => store.reorder("front"))}>Bring to front</button>
        <button data-testid="ctx-back" disabled={view.selectedCount === 0} onclick={() => runMenu(() => store.reorder("back"))}>Send to back</button>
        <div class="ctx-sep"></div>
        <button data-testid="ctx-selectall" onclick={() => runMenu(() => store.selectAll())}>Select all</button>
        <button data-testid="ctx-delete" disabled={view.selectedCount === 0} onclick={() => runMenu(() => store.deleteSelected())}>Delete</button>
      </div>
    {/if}
  </main>

  <footer class="status">
    <button data-testid="zoom-out" onclick={() => store.zoomOut()}>−</button>
    <button data-testid="zoom-reset" onclick={() => store.resetZoom()}>{view.zoom}%</button>
    <button data-testid="zoom-in" onclick={() => store.zoomIn()}>+</button>
    <span class="sep"></span>
    <span data-testid="selection-stats">{view.stats ?? ""}</span>
    <span class="grow"></span>
    {#if view.peers.length > 0}
      <span class="peers" data-testid="peers">
        {#each view.peers as p (p.id)}
          <span class="peer" style="background:{p.color}" title={p.name}>{p.name}</span>
        {/each}
      </span>
    {/if}
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
    /* Match the canvas's default hand-drawn text face so editing is WYSIWYG. */
    font: 20px "Excalifont", "Virgil", "Bradley Hand", "Comic Sans MS", "Segoe Print", cursive;
    border: 1px dashed #4263eb;
    background: transparent;
    resize: none;
    outline: none;
    padding: 0;
  }
  .chart-editor {
    position: absolute;
    display: flex;
    gap: 8px;
    align-items: center;
    padding: 8px 10px;
    background: #fff;
    border: 1px solid #4263eb;
    border-radius: 8px;
    box-shadow: 0 4px 16px #0003;
    z-index: 10;
  }
  .app[data-theme="dark"] .chart-editor { background: #2a2a2a; color: #eee; }
  .chart-editor input[type="text"] { width: 140px; }
  .ctx-backdrop { position: fixed; inset: 0; z-index: 20; padding: 0; border: none; border-radius: 0; background: transparent; cursor: default; }
  .context-menu {
    position: absolute;
    z-index: 21;
    display: flex;
    flex-direction: column;
    min-width: 150px;
    padding: 4px;
    background: #fff;
    border: 1px solid #0003;
    border-radius: 8px;
    box-shadow: 0 6px 20px #0003;
  }
  .app[data-theme="dark"] .context-menu { background: #2a2a2a; color: #eee; border-color: #fff3; }
  .context-menu button {
    border: none;
    background: transparent;
    text-align: left;
    border-radius: 6px;
    padding: 6px 10px;
  }
  .context-menu button:not(:disabled):hover { background: #4263eb22; }
  .context-menu button:disabled { opacity: 0.4; cursor: default; }
  .ctx-sep { height: 1px; margin: 4px 6px; background: #0002; }
  .peers { display: inline-flex; gap: 4px; }
  .peer { color: #fff; font-size: 11px; padding: 2px 8px; border-radius: 10px; }
  .sep { width: 1px; align-self: stretch; background: #0002; margin: 0 4px; }
  .grow { flex: 1; }
  label { display: inline-flex; gap: 4px; align-items: center; font-size: 13px; }
</style>
