# Platform UX

## Purpose

The SwiftUI shell and platform integration that wraps the pure editor core for iOS and iPadOS. It covers the EditorModel bridge, raw touch and Apple Pencil input with palm rejection, two-finger pan/zoom, adaptive layout and theming, the command palette and keyboard shortcuts, localization with RTL, laser/eraser trails, color pickers, zoom controls, and live web embeds.

## Requirements

### Requirement: EditorModel bridge
The system SHALL bridge SwiftUI to the pure EditorController, converting pointer events from view space to scene space via the viewport, publishing a revision counter that drives canvas redraws, and owning the viewport, theme, and zen state (src: Sources/ExcalidrawUI/EditorModel.swift:12).

#### Scenario: Pointer event creates an element
- GIVEN the editor model and an active drawing tool
- WHEN a pointer event is forwarded
- THEN the system SHALL create an element (src: Tests/ExcalidrawUITests/EditorModelTests.swift:17)

#### Scenario: View-to-scene conversion honors zoom
- GIVEN a viewport at zoom 2
- WHEN a view point (20,20) is converted
- THEN the system SHALL produce scene point (10,10) (src: Tests/ExcalidrawUITests/EditorModelTests.swift:33)

### Requirement: Pointer and touch input with palm rejection
The system SHALL capture raw UITouch events via TouchCaptureView and forward phase, location, type (finger or pencil), and normalized pressure (force/maxForce, default 0.5), SHALL escape multi-touch to pan/zoom, and SHALL, once a pencil is active, ignore finger touches until the pencil leaves (src: Sources/ExcalidrawUI/PointerInputView.swift:9).

#### Scenario: Single touch forwards a pointer event
- GIVEN the touch capture view
- WHEN a single finger touch occurs
- THEN the system SHALL forward a pointer event that creates an element (src: Tests/ExcalidrawUITests/EditorModelTests.swift:17)

### Requirement: Two-finger pan and zoom
The system SHALL, with two or more fingers, compute the centroid and spread, derive translation from the centroid delta and scale from the spread ratio, update the viewport via panZoom within the zoom range, and gate the gesture-snapshot path while gesturing (src: Sources/ExcalidrawUI/PointerInputView.swift:197, Sources/ExcalidrawUI/EditorModel.swift:131).

#### Scenario: Pan translates by scaled deltas
- GIVEN the viewport at zoom 2
- WHEN a two-finger pan of (10,20) occurs
- THEN the system SHALL apply scroll deltas of (5,10) (src: Tests/ExcalidrawUITests/EditorModelTests.swift:75)

### Requirement: Apple Pencil hover and squeeze
The system SHALL report pencil proximity via UIHoverGestureRecognizer, drawing a 14×14 accent ring on hover and nil when the pencil leaves, and SHALL, on a UIPencilInteraction squeeze (iOS 17.5+), toggle the eraser tool (src: Sources/ExcalidrawUI/PointerInputView.swift:66, Sources/ExcalidrawUI/EditorView.swift:288).

#### Scenario: Hover draws and clears the ring
- GIVEN a pencil hovering over the canvas
- WHEN the pencil moves and then leaves
- THEN the system SHALL draw a 14×14 accent ring and clear it (nil) on leave (src: Sources/ExcalidrawUI/PointerInputView.swift:66)

#### Scenario: Squeeze toggles the eraser
- GIVEN a pencil squeeze on iOS 17.5+
- WHEN onSqueeze fires
- THEN the system SHALL toggle the eraser tool (src: Sources/ExcalidrawUI/EditorView.swift:288)

### Requirement: Adaptive layout, dark mode, and zen mode
The system SHALL place the toolbar and properties at the bottom in compact (iPhone) layout and at the top in regular (iPad) layout, SHALL toggle the canvas background and renderer color scheme between light and dark themes, and SHALL, in zen mode, hide all chrome but the canvas while showing an Exit button (src: Sources/ExcalidrawUI/EditorView.swift:44).

#### Scenario: Theme and zen toggles flip
- GIVEN the editor model
- WHEN the theme and zen-mode toggles are invoked
- THEN the system SHALL flip the theme and zen state accordingly (src: Tests/ExcalidrawUITests/EditorModelTests.swift:561)

### Requirement: Command palette and keyboard shortcuts
The system SHALL open a fuzzy-search command palette over roughly 24 commands on ⌘K, SHALL select tools with single keys (V/R/D/O/A/L/P/T/E/H…), delete with Backspace/Delete, run undo/redo/copy/cut/paste/duplicate/selectAll/group/ungroup/zoom on ⌘ combinations, spawn a linked flowchart node on Tab, and choose direction with ⌥+arrow (src: Sources/ExcalidrawEditor/CommandRegistry.swift:17, Sources/ExcalidrawEditor/Shortcuts.swift:32, Sources/ExcalidrawUI/EditorView.swift:585).

#### Scenario: Command dispatch runs a command
- GIVEN the command registry
- WHEN a command is dispatched
- THEN the system SHALL execute the corresponding editor action (src: Tests/ExcalidrawUITests/EditorModelTests.swift:195)

### Requirement: Localization with RTL
The system SHALL provide built-in en (ltr), es (ltr), and ar (rtl) locales, SHALL set the locale by BCP-47 tag with English fallback, SHALL translate via t(key) with an English-then-raw-key fallback, and SHALL derive layoutDirection from the locale and apply it to the whole view hierarchy (src: Sources/ExcalidrawUI/EditorModel.swift:263, Sources/ExcalidrawModel/Localization.swift:29).

#### Scenario: Locale changes translate and flip direction
- GIVEN the default en locale
- WHEN the locale is set to es and then ar
- THEN the system SHALL translate the strings and flip the layout direction to RTL for ar (src: Tests/ExcalidrawUITests/EditorModelTests.swift:306)

### Requirement: Laser pointer and eraser trail
The system SHALL hold timestamped laser and eraser dots in scene coordinates in a TrailStore, pruning dots past a 0.7s fade, and SHALL draw age-faded segments via a TimelineView overlay (red width 4 for laser, gray width 10 for eraser), where the laser creates no element and the eraser still erases (src: Sources/ExcalidrawUI/TrailStore.swift:9, Sources/ExcalidrawUI/EditorView+Controls.swift:94).

#### Scenario: Trail dots fade and prune
- GIVEN laser and eraser dots added to the trail store
- WHEN time passes beyond the 0.7s fade
- THEN the system SHALL prune the expired dots (src: Tests/ExcalidrawUITests/TrailTests.swift:8)

#### Scenario: Laser creates no element while eraser erases
- GIVEN the laser tool and the eraser tool
- WHEN a stroke is drawn with each
- THEN the laser SHALL create no element and the eraser SHALL erase (src: Tests/ExcalidrawUITests/TrailTests.swift:65)

### Requirement: Custom color picker and eyedropper
The system SHALL provide a native SwiftUI ColorPicker (with the system eyedropper) for stroke and background colors, SHALL convert between hex and Color, and SHALL disable opacity in the picker (src: Sources/ExcalidrawUI/EditorView+Controls.swift:50, Sources/ExcalidrawUI/EditorView.swift:668).

#### Scenario: Hex parses to a color
- GIVEN a hex color string
- WHEN it is parsed
- THEN the system SHALL produce the corresponding Color (src: Tests/ExcalidrawUITests/EditorViewTests.swift:16)

### Requirement: Zoom controls
The system SHALL provide zoomIn (×1.2), zoomOut (÷1.2), resetZoom (→1.0), and zoomToFit (fit content or selection with margin) about an anchor, clamped to the zoom range, and SHALL report zoomPercent as round(zoom×100) (src: Sources/ExcalidrawUI/EditorModel.swift:369).

#### Scenario: Zoom in and out scale about the anchor
- GIVEN a viewport at zoom 1
- WHEN zoomIn and zoomOut are invoked
- THEN the system SHALL scale by ×1.2 and ÷1.2 within the clamped zoom range (src: Tests/ExcalidrawUITests/EditorModelTests.swift:164)

#### Scenario: Reset returns to 100 percent
- GIVEN a zoomed viewport
- WHEN resetZoom is invoked
- THEN the system SHALL set zoom to 1.0 and zoomPercent to 100 (src: Tests/ExcalidrawUITests/EditorModelTests.swift:183)

### Requirement: Live web embeddables
The system SHALL validate a pasted URL against EmbedAllowList.embedURL (YouTube watch→/embed, youtu.be, Vimeo→player, plus an allowed-host list, rejecting non-http(s) or disallowed hosts), SHALL insert an embeddable element carrying the sanitized URL, SHALL render it as a live WKWebView overlay sized to the element (scaled by zoom) and clipped to 8pt corners, and SHALL suppress web interaction under the selection tool so touches select/move the element while otherwise allowing media interaction (src: Sources/ExcalidrawModel/EmbedAllowList.swift, Sources/ExcalidrawUI/WebEmbedView.swift:9, Sources/ExcalidrawUI/EditorView+Controls.swift:10, Sources/ExcalidrawUI/EditorModel+Embed.swift:3).

#### Scenario: Allowed URL inserts an embeddable with sanitized link
- GIVEN an allowed embed URL
- WHEN it is inserted
- THEN the system SHALL store the sanitized URL in the element's link (src: Tests/ExcalidrawUITests/EmbedInsertTests.swift:7)

#### Scenario: Empty URL is a no-op
- GIVEN an empty URL
- WHEN insertion is attempted
- THEN the system SHALL do nothing (src: Tests/ExcalidrawUITests/EmbedInsertTests.swift:23)
