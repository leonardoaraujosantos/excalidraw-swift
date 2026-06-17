# Scene Rendering (Core Graphics)

## Purpose

The default Core Graphics renderer that turns a scene into pixels behind the `SceneRendering` protocol. It draws every element kind, text, images, and frames, paints an interactive overlay (selection, handles, marquee, snap guides, editing discs, crop), and uses layered caching of shapes and the static scene for smooth interaction during edits.

## Requirements

### Requirement: SceneRendering protocol
The system SHALL define a `SceneRendering` protocol whose Core Graphics backend draws into a y-down context, where `render()` accepts a `skipping` set of element ids (to avoid double-drawing in the layered split) and a `fillBackground` flag (src: Sources/ExcalidrawRender/SceneRendering.swift:9).

#### Scenario: Skipping set excludes elements
- GIVEN a render call with a non-empty `skipping` set
- WHEN the scene is rendered
- THEN the elements in the skipping set SHALL NOT be drawn (src: Sources/ExcalidrawRender/SceneRendering.swift:9)

### Requirement: Viewport and transform
The system SHALL maintain a viewport of `scrollX`, `scrollY`, and `zoom` (identity being origin 0,0 and zoom 1.0), map scene to view as `(x + scrollX) * zoom` (with the corresponding inverse), build the affine transform as `scale(zoom) * translate(scroll)`, and clamp zoom to the range [0.1, 30.0] (src: Sources/ExcalidrawRender/SceneRenderer.swift:14).

#### Scenario: Scene-to-view mapping
- GIVEN a viewport with scroll and zoom
- WHEN a scene point is mapped to view space
- THEN it SHALL equal `(point + scroll) * zoom`, and the inverse SHALL recover the original point (src: Sources/ExcalidrawRender/SceneRenderer.swift:14)

#### Scenario: Zoom is clamped
- GIVEN a zoom value outside [0.1, 30.0]
- WHEN it is applied
- THEN it SHALL be clamped into the range [0.1, 30.0] (src: Sources/ExcalidrawRender/SceneRenderer.swift:14)

### Requirement: Background, grid, culling, and clipping
The system SHALL paint a theme-aware background (`#ffffff` light, `#121212` dark), draw a 20px grid with anti-aliasing disabled when enabled, cull elements outside the viewport using a 100-unit margin, clip frame children to the frame box, rotate each element about its center, and apply per-element opacity (src: Sources/ExcalidrawRender/SceneRenderer.swift:82).

#### Scenario: Visible content is painted
- GIVEN a scene with elements inside the viewport
- WHEN it is rendered
- THEN the output SHALL be non-blank, with ink covering more than 200px (src: Tests/ExcalidrawRenderTests/SceneRenderTests.swift:27)

#### Scenario: Off-screen element is culled
- GIVEN an element positioned far outside the viewport
- WHEN the scene is rendered
- THEN that element SHALL be skipped by culling (src: Tests/ExcalidrawRenderTests/SceneRenderTests.swift:100)

#### Scenario: Frame clipping limits repaint
- GIVEN children clipped to a frame box
- WHEN the scene is rendered
- THEN drawing SHALL be limited to the frame's clip region (src: Tests/ExcalidrawRenderTests/SceneRenderTests.swift:27)

### Requirement: Element dispatch
The system SHALL dispatch each element by kind: text to `TextLayout`, image to decode-and-crop, freedraw to a FreehandKit outline, arrow and shape to `ElementDrawable` plus arrowhead barbs (triangle/diamond/bar, rotated to the segment angle and scaled by size), embeddable and iframe to a rounded-rect placeholder with a diagonal cross, and bound text centered within its container (src: Sources/ExcalidrawRender/SceneRenderer.swift:178).

#### Scenario: Each kind routes to its drawer
- GIVEN elements of differing kinds in a scene
- WHEN the scene is rendered
- THEN each element SHALL be drawn by the handler for its kind (text, image, freedraw, arrow/shape, embeddable/iframe) (src: Tests/ExcalidrawRenderTests/SceneRenderTests.swift:49)

### Requirement: Op-set rendering
The system SHALL render Drawable op-sets such that `.fillPath` is a solid fill, `.fillSketch` is a stroked hatch (line weight from `fillWeight`, else `strokeWidth/2`), and `.path` is a stroked outline using round cap and join with an optional dash pattern (src: Sources/ExcalidrawRender/SceneRenderer.swift:308).

#### Scenario: Fill sketch is stroked
- GIVEN a Drawable containing a `.fillSketch` op-set
- WHEN it is rendered
- THEN it SHALL be stroked at a weight of `fillWeight` or `strokeWidth/2` (src: Sources/ExcalidrawRender/SceneRenderer.swift:308)

### Requirement: ElementDrawable dispatch
The system SHALL build the Drawable per shape kind: rectangle (plain, or rounded via sampled corner arcs), diamond (4 points), ellipse (rough curve with 2 strokes when roughness greater than zero), and line (open polyline when 2 points or fewer, a curve when more than 2 points and rounded, a polygon when closed — first and last points within 40 units of each other) (src: Sources/ExcalidrawRender/ElementDrawable.swift:24).

#### Scenario: Line closes into a polygon
- GIVEN a line whose first and last points are within 40 units of each other
- WHEN its Drawable is built
- THEN it SHALL be treated as a closed polygon (src: Sources/ExcalidrawRender/ElementDrawable.swift:24)

#### Scenario: Rounded rectangle uses corner arcs
- GIVEN a rectangle with rounded corners
- WHEN its Drawable is built
- THEN its corners SHALL be sampled as arcs (src: Sources/ExcalidrawRender/ElementDrawable.swift:24)

### Requirement: RoughOptions building
The system SHALL build rough options from element properties (seed, roughness, strokeWidth, fillStyle, fill, and strokeStyle mapped to a dash pattern — dashed `[8, 8+sw]`, dotted `[1.5, 6+sw]`), reduce roughness for small shapes (halved, capped at 2.5), preserve vertices for artist roughness and polyline editing, treat closed lines and freedraw loops as fillable, and disable fill for transparent colors (`"transparent"` or any value ending in `00`) (src: Sources/ExcalidrawRender/RoughOptionsBuilder.swift:13).

#### Scenario: Transparent fill disables fill
- GIVEN an element whose background color is `"transparent"` or ends in `00`
- WHEN its rough options are built
- THEN fill SHALL be disabled (src: Sources/ExcalidrawRender/RoughOptionsBuilder.swift:13)

#### Scenario: Dashed stroke style maps to a dash pattern
- GIVEN an element with a dashed stroke style and stroke width `sw`
- WHEN its rough options are built
- THEN the dash pattern SHALL be `[8, 8+sw]` (src: Sources/ExcalidrawRender/RoughOptionsBuilder.swift:13)

### Requirement: Text layout
The system SHALL lay out text by splitting on newlines and rendering each line with a Core Text `CTLine` at `fontSize * lineHeight` spacing, applying a flip matrix for the y-down context, measuring the size as the widest line by the total height, and enabling subpixel and glyph anti-aliasing for crisp text at any zoom (src: Sources/ExcalidrawRender/TextLayout.swift:16).

#### Scenario: Multi-line text is laid out per line
- GIVEN text containing newlines
- WHEN it is laid out
- THEN each line SHALL be rendered at `fontSize * lineHeight` spacing and the measured size SHALL be the widest line by total height (src: Sources/ExcalidrawRender/TextLayout.swift:16)

### Requirement: Font registry and family mapping
The system SHALL register bundled TTF/OTF/WOFF2 fonts from the app bundle `Fonts/` directory, map `FontFamily` ids to preferred PostScript names when registered (else system fallbacks: Excalifont/Virgil/Nunito to Bradley Hand, Cascadia to Menlo), validate a mapping by constructing a `CTFont` and comparing PostScript names, cache the results, and make registration idempotent (src: Sources/ExcalidrawRender/FontRegistry.swift:14).

#### Scenario: Family maps to a fallback when unregistered
- GIVEN a `FontFamily` whose bundled font is not registered
- WHEN its font is resolved
- THEN it SHALL fall back to the mapped system font (e.g. Excalifont to Bradley Hand, Cascadia to Menlo) (src: Tests/ExcalidrawRenderTests/FontRegistryTests.swift:6)

#### Scenario: Registration is idempotent
- GIVEN fonts already registered
- WHEN registration runs again
- THEN it SHALL not fail or double-register (src: Tests/ExcalidrawRenderTests/FontRegistryTests.swift:32)

### Requirement: Image rendering with crop
The system SHALL render images by decoding the data URL (cached by `fileId`), cropping to the natural-pixel sub-region via `CGImage.cropping`, scaling to the element rect, and vertically flipping for the y-down context (src: Sources/ExcalidrawRender/SceneRenderer.swift:355).

#### Scenario: Cropped image fills the element rect
- GIVEN an image element with a crop region
- WHEN it is rendered
- THEN the cropped sub-region SHALL be scaled to the element rect and flipped for y-down (src: Sources/ExcalidrawRender/SceneRenderer.swift:355)

### Requirement: Frame rendering
The system SHALL render a frame as a rounded rectangle (corner radius 8) with a 1px theme-adjusted border, and draw its name label above the top-left corner at `y − 18` using font size 12 (src: Sources/ExcalidrawRender/SceneRenderer.swift:228).

#### Scenario: Frame name label is positioned above
- GIVEN a frame with a name
- WHEN it is rendered
- THEN the label SHALL appear above the top-left corner at `y − 18` in font size 12 (src: Sources/ExcalidrawRender/SceneRenderer.swift:228)

### Requirement: Interactive overlay
The system SHALL draw an interactive overlay containing a selection box with 8 square handles (white with violet accent, sized by `size/zoom` so they stay screen-constant), a marquee (dashed `[4,4]`, fill alpha 0.08), snap guide lines (red), a rotation handle circle, linear-edit point and midpoint discs, and a crop frame with handles (src: Sources/ExcalidrawRender/InteractiveRenderer.swift:37).

#### Scenario: Handles stay screen-constant
- GIVEN a selected element at a given zoom
- WHEN the selection handles are drawn
- THEN their size SHALL be `size/zoom` so they appear constant on screen (src: Tests/ExcalidrawRenderTests/OverlayAndExportTests.swift:26)

#### Scenario: Marquee is drawn
- GIVEN an active marquee selection
- WHEN the overlay is drawn
- THEN the marquee SHALL be a dashed `[4,4]` rectangle filled at alpha 0.08 (src: Tests/ExcalidrawRenderTests/OverlayAndExportTests.swift:47)

### Requirement: Shape and static-layer caching
The system SHALL cache the Drawable per element id and regenerate it when the element value changes (not merely its version), and SHALL cache the rasterized static scene (all elements except those in-flight) keyed on a token that is invalidated by any change to the scene, viewport, theme, or size (src: Sources/ExcalidrawRender/ShapeCache.swift:16, Sources/ExcalidrawRender/StaticLayerCache.swift:13).

#### Scenario: Drawable regenerated on value change
- GIVEN a cached Drawable for an element
- WHEN the element's value changes
- THEN the Drawable SHALL be regenerated (src: Sources/ExcalidrawRender/ShapeCache.swift:16)

#### Scenario: Static layer invalidated on viewport change
- GIVEN a cached static scene
- WHEN the viewport, theme, scene, or size changes
- THEN the cache token SHALL be invalidated and the static scene re-rasterized (src: Sources/ExcalidrawRender/StaticLayerCache.swift:13)
