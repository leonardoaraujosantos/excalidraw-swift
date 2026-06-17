# Metal GPU Rendering

## Purpose

An optional GPU renderer that sits behind the same `SceneRendering` protocol as the Core Graphics renderer, with automatic CG fallback when Metal is unsupported. It tessellates rough shapes, freedraw outlines, dashed strokes, and image quads into colored triangles, rasterizes them on the GPU with 4× MSAA, and (in the editor) presents direct-to-`CAMetalLayer` with a Core Graphics text/overlay pass on top. Text is intentionally never sent to the GPU, and the GPU path repaints the full visible region every frame instead of honoring the incremental-redraw clip.

## Requirements

### Requirement: GPU scene rendering with Core Graphics fallback
The system SHALL provide `MetalSceneRenderer` conforming to `SceneRendering`, rendering rough shapes (rectangle, diamond, ellipse, line, arrow) tessellated and rasterized on the GPU with 4× MSAA, while compositing each frame as background+grid (Core Graphics) → GPU shape image → remaining Core Graphics elements (text, images, frames). Its failable initializer SHALL return `nil` when Metal is unavailable so the app silently uses the Core Graphics renderer instead (src: Sources/ExcalidrawMetal/MetalSceneRenderer.swift:20, Sources/ExcalidrawRender/SceneRendering.swift:9).

#### Scenario: Metal renderer matches Core Graphics output
- GIVEN a scene with rough shapes and a background
- WHEN the Metal renderer and the Core Graphics renderer each render it
- THEN the Metal renderer SHALL produce a non-empty image that agrees with the Core Graphics output on background corners (src: Tests/ExcalidrawMetalTests/MetalSceneRendererTests.swift:96)

#### Scenario: Fallback when Metal is unsupported
- GIVEN a device or environment where Metal is not available
- WHEN the renderer is constructed
- THEN construction SHALL return `nil` and the app SHALL use the Core Graphics renderer transparently (src: Sources/ExcalidrawMetal/MetalSceneRenderer.swift:20)

### Requirement: Scene-to-GPU geometry tessellation
The system SHALL convert a `Scene` into colored triangles expressed in scene coordinates, tessellating rough shapes, solid/dashed/dotted strokes, freedraw outlines, and image quads, while skipping GPU-ineligible elements (text, frames, embeddables, and frame-clipped children) and returning their ids via `handledIDs` so the Core Graphics overlay skips them; it SHALL restrict output to a culling region expanded by a 100-unit margin (src: Sources/ExcalidrawMetal/SceneGeometry.swift:10).

#### Scenario: Rough shapes handled, text skipped
- GIVEN a scene containing rough shapes and a text element
- WHEN geometry is built
- THEN the rough shapes SHALL be tessellated to triangles and the text element id SHALL be reported as not GPU-handled so the CG overlay draws it (src: Tests/ExcalidrawMetalTests/MetalSceneRendererTests.swift:31)

#### Scenario: Frame-clipped children skipped
- GIVEN a scene with a dashed shape and a frame-clipped child
- WHEN geometry is built
- THEN the dashed shape SHALL be tessellated while the framed child is left to the Core Graphics overlay (src: Tests/ExcalidrawMetalTests/MetalSceneRendererTests.swift:46)

### Requirement: Polygon and stroke triangulation
The system SHALL triangulate closed polygons by ear-clipping with a centroid-fan fallback for degenerate or self-intersecting input, SHALL flatten rough cubic Béziers into 10-segment polylines, SHALL stroke paths with round caps and round joins only past an 18° turn threshold, and SHALL split dashed/dotted strokes into "on" runs matching Core Graphics `setLineDash` and stroke each as a solid run (src: Sources/ExcalidrawMetal/PolygonTriangulator.swift:11, Sources/ExcalidrawMetal/Tessellator.swift:22).

#### Scenario: Dashed geometry differs from solid
- GIVEN the same path tessellated once as solid and once as dashed
- WHEN the resulting triangle geometry is compared
- THEN the dashed geometry SHALL differ from the solid geometry, reflecting the split into "on" runs (src: Tests/ExcalidrawMetalTests/MetalSceneRendererTests.swift:46)

### Requirement: Tessellation geometry cache
The system SHALL memoize tessellated vertices per element and theme, invalidating an entry when the element value changes (by `==`) or the theme changes. Because vertices are baked in scene coordinates with color, the cache SHALL stay valid across pan and zoom (only the per-frame clip transform changes), so steady-state frames skip re-tessellation (src: Sources/ExcalidrawMetal/GeometryCache.swift:13).

#### Scenario: Cached second frame is faster
- GIVEN a scene rendered once so its geometry is cached
- WHEN the same scene is rendered again
- THEN the second frame SHALL reuse cached geometry and complete faster than the first (src: Tests/ExcalidrawMetalTests/MetalSceneRendererTests.swift:141)

### Requirement: Packed RGBA8 vertex color
The system SHALL pack each vertex color as RGBA8 into a single 32-bit word bitcast to a float (giving three floats per vertex), unpack it in the vertex shader, and premultiply it for source-over blending, reducing per-vertex color bandwidth by roughly 25% versus four color floats (src: Sources/ExcalidrawMetal/SceneGeometry.swift:345, Sources/ExcalidrawMetal/MetalRenderContext.swift:365).

#### Scenario: Color survives pack and unpack
- GIVEN a colored vertex
- WHEN its color is packed into one 32-bit word and unpacked in the vertex shader
- THEN the premultiplied color SHALL render correctly under source-over blending (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:365)

### Requirement: Persistent GPU resources with 4× MSAA
The system SHALL render into a 4× MSAA texture and resolve it, persisting the MSAA and resolve targets and the vertex buffers across frames and rebuilding them only when the pixel size changes. It SHALL grow the vertex buffer with 2× headroom and keep a separate vertex buffer for image quads (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:47).

#### Scenario: Targets rebuilt only on size change
- GIVEN render targets sized for the current drawable
- WHEN consecutive frames render at the same pixel size
- THEN the MSAA/resolve targets and vertex buffers SHALL be reused without rebuilding (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:47)

### Requirement: Frame and command model
The system SHALL represent a renderable frame as colored-triangle vertices, image-quad vertices, an ordered list of draw `Command`s (each a triangle range OR an image with texture and opacity), a scene→clip transform, and a clear color, preserving z-order by interleaving triangle runs and image commands in draw order (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:24).

#### Scenario: Z-order preserved across mixed elements
- GIVEN a scene with shapes and images interleaved by index
- WHEN the frame's draw commands are built
- THEN triangle runs and image commands SHALL be ordered to match the elements' draw order (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:24)

### Requirement: Image texture cache
The system SHALL decode `BinaryFileData` into premultiplied RGBA8 `MTLTexture`s via a `CGContext` (normalizing arbitrary source formats), cache them by file id, flip them vertically so UV (0,0) is the top-left, use `.shared` storage, and apply opacity at composite time (src: Sources/ExcalidrawMetal/ImageTextureCache.swift:23).

#### Scenario: Image decoded once and reused
- GIVEN an image element whose file has been decoded to a texture
- WHEN the same file id is requested again
- THEN the cached premultiplied RGBA8 texture SHALL be returned without re-decoding (src: Sources/ExcalidrawMetal/ImageTextureCache.swift:23)

### Requirement: Direct-to-drawable present path
The system SHALL support rendering straight into a `CAMetalDrawable`'s texture as the resolve target with no off-screen read-back and an asynchronous present, skipping `CGContext` creation and the texture→CPU copy (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:179, Sources/ExcalidrawMetal/MetalSceneRenderer.swift:100).

#### Scenario: No read-back on the direct path
- GIVEN a `CAMetalDrawable` to present into
- WHEN a frame is rendered on the direct path
- THEN the frame SHALL be resolved into the drawable texture and presented asynchronously without copying pixels back to the CPU (src: Sources/ExcalidrawMetal/MetalRenderContext.swift:179)

### Requirement: Editor hybrid GPU + Core Graphics split
The system SHALL, in the editor, draw GPU-eligible shapes, freedraw, dashed strokes, and images straight to a `CAMetalLayer` drawable while drawing text, frames, embeddables, and the interactive overlay on a Core Graphics layer above it, and the Core Graphics pass SHALL skip elements reported by `SceneGeometry.isGPUHandled` to avoid double-drawing (src: Sources/ExcalidrawUI/EditorMetalCanvas.swift:1, Sources/ExcalidrawUI/EditorModel+Renderer.swift:63).

#### Scenario: Overlay skips GPU-handled elements
- GIVEN the editor running the hybrid path
- WHEN the Core Graphics overlay pass runs
- THEN it SHALL skip every element for which `SceneGeometry.isGPUHandled` is true (src: Sources/ExcalidrawUI/EditorModel+Renderer.swift:63)

### Requirement: Runtime CPU/Metal renderer toggle
The system SHALL switch between `.coreGraphics` and `.metal` renderers at runtime via `setRenderer`, falling back to Core Graphics silently when Metal is unavailable, and SHALL invalidate the static and gesture caches to force a repaint on switch. It SHALL expose `isMetalAvailable` and `toggleRenderer`, with availability derived from `MetalSceneRenderer.isSupported` (src: Sources/ExcalidrawUI/EditorModel+Renderer.swift:29).

#### Scenario: Defaults to Core Graphics
- GIVEN a freshly constructed editor model
- WHEN no renderer has been explicitly selected
- THEN the active renderer SHALL be Core Graphics (src: Tests/ExcalidrawUITests/RendererToggleTests.swift:8)

#### Scenario: Toggle respects availability
- GIVEN Metal may or may not be supported
- WHEN `toggleRenderer` is invoked
- THEN it SHALL switch to Metal only when supported and otherwise remain on Core Graphics (src: Tests/ExcalidrawUITests/RendererToggleTests.swift:8)

### Requirement: In-app renderer benchmark
The system SHALL provide a benchmark screen comparing CPU, Metal (read-back), Metal-direct, and editor-hybrid frame times with a per-phase breakdown (geometry, GPU, overlay) and speedup ratios, over synthetic scenes of kinds `.shapes`, `.mixed`, and `.all` at variable element counts, plus a live pan/zoom stress test reporting FPS (src: Sources/ExcalidrawUI/RendererBenchmarkView.swift:59, Sources/ExcalidrawUI/RendererBenchmark.swift:34).

#### Scenario: Benchmark produces timed rows
- GIVEN a synthetic scene of a given kind and element count
- WHEN the benchmark runs
- THEN it SHALL produce rows with positive CPU times and populate Metal/hybrid times and speedup ratios when Metal is available (src: Tests/ExcalidrawUITests/RendererBenchmarkTests.swift:7)

### Requirement: No GPU text atlas
The system SHALL NOT tessellate text to the GPU; text SHALL remain on the Core Graphics overlay so it stays crisp at any zoom level (src: Sources/ExcalidrawMetal/MetalSceneRenderer.swift:12).

#### Scenario: Text always drawn by Core Graphics
- GIVEN a scene containing text elements
- WHEN the Metal path renders the frame
- THEN text SHALL NOT be sent to the GPU and SHALL be drawn by the Core Graphics overlay instead (src: Sources/ExcalidrawMetal/MetalSceneRenderer.swift:12)

### Requirement: Full-viewport GPU repaint
The system SHALL, on the GPU path, ignore the incremental-redraw clip rectangle and repaint the full visible region each frame. This trade-off is idempotent (the output is unaffected) and is purely a performance characteristic of the GPU path (src: Sources/ExcalidrawMetal/SceneGeometry.swift:87).

#### Scenario: Clip rectangle ignored on the GPU path
- GIVEN an incremental-redraw clip rectangle for a partial update
- WHEN the GPU path renders the frame
- THEN it SHALL repaint the whole visible region rather than only the clipped area, producing the same pixels as a full redraw (src: Sources/ExcalidrawMetal/SceneGeometry.swift:87)
