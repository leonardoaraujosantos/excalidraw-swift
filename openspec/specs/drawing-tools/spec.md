# Drawing Tools

## Purpose

The tool model and element-creation behavior of the editor: the active `Tool`, which tools create elements, and how each kind of element (shapes, freedraw, text, image) is created, sized, styled, and committed. Creation tools revert to selection after producing one element unless the tool is locked, and new elements inherit the current-item style defaults.

## Requirements

### Requirement: Tool model
The system SHALL provide a `Tool` enum covering selection, rectangle, diamond, ellipse, line, arrow, freedraw, text, postit (sticky note), table, frame, eraser, laser, and hand, where the rectangle, diamond, ellipse, line, arrow, freedraw, and frame tools are element-creating (their `elementKind` is non-`nil`) and the remaining tools are non-creating. A creating tool SHALL revert to selection after producing one element unless the tool is locked (src: Sources/ExcalidrawEditor/Tool.swift:5).

#### Scenario: Shape tool reverts after one shape
- GIVEN the rectangle tool is active and not locked
- WHEN a rectangle is created by a drag
- THEN the active tool SHALL revert to selection (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:31)

#### Scenario: Non-creating tools create no element
- GIVEN a non-creating tool such as selection, eraser, laser, or hand
- WHEN it is active
- THEN its `elementKind` SHALL be `nil` so no element is created on pointer interaction (src: Sources/ExcalidrawEditor/Tool.swift:22)

### Requirement: Drag-to-create shapes
The system SHALL create a rectangle, diamond, ellipse, line, or arrow from a pointer-down → pointer-move → pointer-up gesture, sizing the new element by the drag extent, and SHALL give a newly created arrow a default end arrowhead (src: Sources/ExcalidrawEditor/EditorController.swift:226).

#### Scenario: Rectangle sized by drag then reverts
- GIVEN the rectangle tool is active
- WHEN the pointer drags from (10,10) to (60,40)
- THEN a 50×30 rectangle SHALL be created, selected, and the tool SHALL revert to selection (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:31)

#### Scenario: New arrow gets a default end arrowhead
- GIVEN the arrow tool is active
- WHEN an arrow is created by a drag
- THEN the arrow SHALL have its end arrowhead set to the default arrow head (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:180)

### Requirement: Freedraw with pressure
The system SHALL accumulate point and pressure samples into a freedraw element as the pointer moves, recording each sampled point and its pressure in order (src: Sources/ExcalidrawEditor/EditorController.swift:417).

#### Scenario: Points and pressures accumulate in order
- GIVEN the freedraw tool is active
- WHEN the pointer samples points (0,0), (10,5), (20,0) with pressures 0.3, 0.6, 0.9
- THEN the freedraw element SHALL store those points and pressures in order and the tool SHALL revert to selection (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:166)

### Requirement: Text creation and editing
The system SHALL create an empty text element at a point and enter editing, support multi-line text split on `\n`, auto-size the width from the longest line and the height from line count × line height, and carry font family, font size, text alignment, and vertical alignment. A text element MAY bind to a container via `containerId`; setting an unbound text element's content empty SHALL delete it, while a bound text element SHALL be kept. The system SHALL support updating the font on multiple selected text elements, and text edits SHALL be undoable (src: Sources/ExcalidrawEditor/EditorController+Commands.swift:68).

#### Scenario: Create and set text sizes the element
- GIVEN a newly created empty text element
- WHEN multi-line text is set on it
- THEN its width and height SHALL both become greater than zero (src: Tests/ExcalidrawEditorTests/TextAndImageTests.swift:12)

#### Scenario: Empty unbound text is removed
- GIVEN an unbound text element
- WHEN its content is set to empty
- THEN the element SHALL be removed and dropped from the selection (src: Tests/ExcalidrawEditorTests/TextAndImageTests.swift:23)

#### Scenario: Text edit is undoable
- GIVEN a text element created and given content in one operation
- WHEN undo is invoked
- THEN the element SHALL be removed, restoring the prior state (src: Tests/ExcalidrawEditorTests/TextAndImageTests.swift:45)

### Requirement: Image insertion
The system SHALL insert an image element from supplied file data, recording its natural dimensions and crop state, registering the file in the scene, selecting the new element, and reverting the tool to selection (src: Sources/ExcalidrawEditor/EditorController+Commands.swift:142).

#### Scenario: Inserted image registered and selected
- GIVEN image file data with natural dimensions 100×80
- WHEN the image is inserted
- THEN an image element with those dimensions SHALL be created, its file stored in the scene, and the element selected (src: Tests/ExcalidrawEditorTests/TextAndImageTests.swift:31)

### Requirement: Eraser single-undo deletion
The system SHALL, with the eraser tool, delete all elements touched during one erase gesture within a single undo step (src: Sources/ExcalidrawEditor/EditorController.swift:495).

#### Scenario: Erase then undo restores
- GIVEN an element under the eraser
- WHEN the eraser deletes it and undo is invoked
- THEN the element SHALL be restored in a single undo step (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:189)

### Requirement: Current-item style defaults
The system SHALL apply the current-item style to newly created elements, including stroke and background colors, stroke width, fill style, stroke style, roughness, opacity, font family and size, elbowed flag, rounded edges, and start/end arrowheads (src: Sources/ExcalidrawEditor/CurrentItemProperties.swift:1).

#### Scenario: New element inherits current-item style
- GIVEN the current-item style with a configured stroke color, stroke width, fill style, and end arrowhead
- WHEN a new element is created
- THEN it SHALL inherit those style values (src: Sources/ExcalidrawEditor/CurrentItemProperties.swift:1)
