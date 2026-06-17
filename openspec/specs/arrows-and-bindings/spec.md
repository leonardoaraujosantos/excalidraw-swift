# Arrows & Bindings

## Purpose

Arrows that attach to shapes, follow them as they move and resize, optionally route orthogonally (elbow style) with pinnable segments, and carry configurable arrowheads. This capability keeps connectors visually correct under editing and is kept behaviorally compatible with excalidraw.com.

## Requirements

### Requirement: Bindable target detection and binding point
The system SHALL treat rectangle, diamond, ellipse, text, image, frame, magicframe, embeddable, and iframe elements as bindable targets, and SHALL find the smallest bindable element whose expanded bounds contain a given point, excluding a supplied set of elements (src: Sources/ExcalidrawGeometry/Binding.swift:12).

#### Scenario: Smallest containing bindable is chosen
- GIVEN a point inside the expanded bounds of multiple bindable elements
- WHEN a bindable target is requested
- THEN the system SHALL return the smallest such element, excluding any supplied elements (src: Tests/ExcalidrawGeometryTests/HitTestTests.swift:80)

### Requirement: Fixed-point binding conversion
The system SHALL convert a scene point into a fixed-point ratio in [0, 1] on each axis relative to an element's bounds, and SHALL convert that ratio back to a scene point, so a binding tracks the target as it moves or resizes (src: Sources/ExcalidrawGeometry/Binding.swift:41).

#### Scenario: Ratio round-trips through bounds
- GIVEN a scene point and an element's bounds
- WHEN the point is converted to a [0,1] ratio and back
- THEN the system SHALL reproduce the original scene point for those bounds (src: Sources/ExcalidrawGeometry/Binding.swift:41)

### Requirement: Arrow binding on creation and reposition
The system SHALL bind an arrow's endpoints to nearby bindable shapes when binding is enabled, recording a `FixedPointBinding` (elementId, fixedPoint, mode) for each bound endpoint and registering the arrow in the target shape's `boundElements`. The system SHALL recompute the affected endpoints when a bound shape moves or resizes (src: Sources/ExcalidrawEditor/EditorController+Binding.swift:6).

#### Scenario: Arrow follows a moved target
- GIVEN an arrow bound to a shape
- WHEN the shape is moved
- THEN the system SHALL recompute the arrow's bound endpoint so the arrow follows the shape (src: Tests/ExcalidrawEditorTests/MermaidParserTests.swift:39)

### Requirement: Orthogonal (elbow) routing
The system SHALL, when an arrow is elbowed, route it with axis-aligned segments from start to end by running A* over a non-uniform grid built from the involved element bounds plus endpoint headings, passing through bound boxes and avoiding obstacles, and SHALL simplify the result by merging collinear and removing short segments (src: Sources/ExcalidrawGeometry/ElbowArrow.swift:11).

#### Scenario: Elbow route is axis-aligned
- GIVEN an elbowed arrow between two points
- WHEN the route is computed
- THEN the system SHALL produce a path of axis-aligned segments connecting start to end (src: Tests/ExcalidrawGeometryTests/ElbowArrowTests.swift:1)

### Requirement: Elbow segment manipulation
The system SHALL identify the fixable interior segments and all draggable segments of an elbow arrow, and SHALL move a segment perpendicular to its direction — shifting an interior segment in place, or inserting an auto-pinned bend when an end segment is moved. The system SHALL reanchor endpoints to follow moved shapes while preserving pinned interior segments, SHALL clear pins and re-route on `resetElbowShape`, and SHALL keep points and bindings intact when elbow mode is toggled (src: Sources/ExcalidrawGeometry/ElbowArrow.swift:85).

#### Scenario: Creating an elbow yields axis-aligned points
- GIVEN an arrow set to elbow mode between two shapes
- WHEN it is routed
- THEN the system SHALL produce at least 4 axis-aligned points (src: Tests/ExcalidrawEditorTests/ElbowArrowEditorTests.swift:14)

#### Scenario: Moving an end segment inserts an auto-pinned bend
- GIVEN an elbow arrow's first (end) segment
- WHEN that segment is dragged perpendicular to its direction
- THEN the system SHALL insert a new bend and auto-pin it (src: Tests/ExcalidrawEditorTests/ElbowArrowEditorTests.swift:143)

#### Scenario: Reset clears pins and re-routes
- GIVEN an elbow arrow with pinned segments
- WHEN `resetElbowShape` is invoked
- THEN the system SHALL clear all pins and re-route the arrow (src: Sources/ExcalidrawEditor/EditorController+Elbow.swift:1)

### Requirement: Arrowheads
The system SHALL maintain start and end arrowhead defaults on the current-item style, defaulting the end arrowhead to Arrow and the start arrowhead to none. The system SHALL provide `setStartArrowhead` and `setEndArrowhead`, each updating the defaults and applying the choice to any selected arrows, with options None, Arrow, Triangle, and Diamond (src: Sources/ExcalidrawUI/EditorModel+Arrowheads.swift:6).

#### Scenario: Default arrowheads
- GIVEN a freshly created arrow using current-item defaults
- WHEN its arrowheads are read
- THEN the end arrowhead SHALL be Arrow and the start arrowhead SHALL be none (src: Tests/ExcalidrawUITests/ArrowheadTests.swift:21)

#### Scenario: Set end arrowhead applies to selection
- GIVEN one or more selected arrows
- WHEN `setEndArrowhead` is called with Triangle
- THEN the system SHALL update the default and set each selected arrow's end arrowhead to Triangle (src: Tests/ExcalidrawUITests/ArrowheadTests.swift:48)
