# Smart Features

## Purpose

Assistive editing capabilities that help users produce clean, well-aligned diagrams with less manual effort. These features layer on top of the core editor: object and gap snapping during drags, freehand shape recognition with a hold-to-snap dwell gesture, flowchart node spawning from selected shapes, and per-element hyperlinks.

## Requirements

### Requirement: Object and gap snapping
The system SHALL, when snapping is enabled, snap the edges and centers of a dragged element to nearby static elements within an 8-unit threshold and snap gaps to equal spacing, SHALL show snap guide lines during the drag and clear them on pointer-up, and SHALL keep snapping disabled by default (src: Sources/ExcalidrawEditor/EditorController.swift:22).

#### Scenario: Edge snaps to a nearby element within threshold
- GIVEN snapping is enabled and a static element with an edge at x=0
- WHEN a dragged element edge comes within the 8-unit threshold of x=0
- THEN the system SHALL snap that edge to x=0 (src: Tests/ExcalidrawEditorTests/SnapIntegrationTests.swift:13)

#### Scenario: Gap snapping equalizes spacing
- GIVEN two static elements with a gap between them and snapping enabled
- WHEN element C is dragged between them
- THEN the system SHALL snap C to center the gap at x=60 (src: Tests/ExcalidrawEditorTests/SnapIntegrationTests.swift:65)

#### Scenario: Guide lines clear on pointer-up
- GIVEN snap guide lines are shown during a drag
- WHEN the pointer is released
- THEN the system SHALL clear the snap guide lines (src: Tests/ExcalidrawEditorTests/SnapIntegrationTests.swift:65)

### Requirement: Freehand shape recognition
The system SHALL recognize a freehand stroke as a clean shape — rectangle, ellipse, diamond, line, triangle, pentagon, hexagon, star, heart, cloud, or speech-bubble — SHALL preserve the stroke's styling, SHALL keep the recognized result selected as a single undo step, and SHALL return the recognized type or nil when no shape is recognized (src: Sources/ExcalidrawEditor/EditorController+ShapeRecognition.swift:1).

#### Scenario: Square stroke becomes a rectangle
- GIVEN a freehand stroke roughly forming a square
- WHEN recognition runs
- THEN the system SHALL return a rectangle element (src: Tests/ExcalidrawEditorTests/ShapeRecognitionTests.swift:25)

#### Scenario: Triangle stroke becomes a 4-point polygon
- GIVEN a freehand stroke roughly forming a triangle
- WHEN recognition runs
- THEN the system SHALL return a polygon line of 4 points (src: Tests/ExcalidrawEditorTests/ShapeRecognitionTests.swift:50)

#### Scenario: Star stroke becomes an 11-point polygon with preserved style
- GIVEN a styled freehand stroke roughly forming a star
- WHEN recognition runs
- THEN the system SHALL return an 11-point polygon preserving the stroke styling (src: Tests/ExcalidrawEditorTests/ShapeRecognitionTests.swift:81)

### Requirement: Hold-to-snap dwell
The system SHALL, while drawing a freehand stroke with recognition enabled, arm a 0.6s dwell timer that resets only when movement exceeds 6 points, and SHALL, when the timer fires, finalize the stroke and snap it to a clean shape while suppressing the normal pointer-up handler (src: Sources/ExcalidrawUI/PointerInputView.swift:43).

#### Scenario: Dwell fires and snaps the stroke
- GIVEN a freehand stroke is being drawn with recognition enabled and the pointer is held still
- WHEN the 0.6s dwell timer fires
- THEN the system SHALL finalize and snap the stroke to a clean shape and suppress the normal pointer-up handler (src: Tests/ExcalidrawUITests/EditorModelTests.swift:332)

#### Scenario: Recognition respects the toggle
- GIVEN recognition is disabled
- WHEN a stroke is drawn and released
- THEN the system SHALL NOT snap the stroke to a clean shape (src: Tests/ExcalidrawUITests/EditorModelTests.swift:361)

### Requirement: Flowchart node spawning
The system SHALL spawn a node from a single selected bindable shape in the up/down/left/right direction, copying its shape, size, and style and offsetting it in that direction with staggering to avoid overlap among multiple same-direction nodes, SHALL connect the new node with an elbow arrow bound at both ends within a single undo step, SHALL select the new node, and SHALL reject non-bindable (linear) sources (src: Sources/ExcalidrawEditor/EditorController+Flowchart.swift:1).

#### Scenario: Spawn right creates a node and bound elbow arrow
- GIVEN a single bindable shape is selected
- WHEN a node is spawned to the right
- THEN the system SHALL create a new node and a bound elbow arrow connecting them in one undo step (src: Tests/ExcalidrawEditorTests/FlowchartTests.swift:13)

#### Scenario: Reject spawning from a linear source
- GIVEN a single linear element (arrow) is selected
- WHEN a node spawn is requested
- THEN the system SHALL reject the operation (src: Tests/ExcalidrawEditorTests/FlowchartTests.swift:80)

### Requirement: Element hyperlinks
The system SHALL attach a trimmed http(s) URL to an element via setLink, SHALL clear the link when given nil or an empty string, SHALL expose the link of the single selected element, and SHALL support links on any element type (src: Sources/ExcalidrawEditor/EditorController+Commands.swift:10).

#### Scenario: Set then clear a link
- GIVEN an element with no link
- WHEN setLink is called with an http(s) URL and later with nil or empty
- THEN the system SHALL store the trimmed URL and then clear it (src: Tests/ExcalidrawEditorTests/ElementLinkTests.swift:1)

#### Scenario: Multi-selection has no single link
- GIVEN multiple elements are selected
- WHEN the selection link is queried
- THEN the system SHALL return nil (src: Tests/ExcalidrawEditorTests/ElementLinkTests.swift:40)
