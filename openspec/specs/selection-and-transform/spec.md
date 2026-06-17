# Selection & Transform

## Purpose

Selecting elements and transforming them: move, resize, and rotate; group, align, flip, reorder, lock, and duplicate; copy and paste across the document; interactive point-by-point editing of lines and arrows; and cropping images. This capability is the primary direct-manipulation surface of the editor and every operation is undoable.

## Requirements

### Requirement: Selection and multi-select
The system SHALL select the element at a point on a single click, ignoring locked elements; SHALL toggle additive selection when Ctrl/Cmd is held during a click; and SHALL select all elements fully contained by a box dragged from empty space. The system SHALL maintain the selection as a `Set<String>` of element ids and SHALL provide `selectAll` and `clearSelection` operations (src: Sources/ExcalidrawEditor/EditorController.swift:10).

The system SHALL show 9 transform handles (8 resize/scale handles plus 1 rotation handle) only when the selection tool is active and the selection is non-empty, and SHALL suppress them while linear-point editing or image cropping is active (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:61).

#### Scenario: Single click selects topmost unlocked element
- GIVEN a scene with overlapping elements at a point
- WHEN the point is single-clicked with the selection tool
- THEN the system SHALL select the topmost non-locked element at that point (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:61)

#### Scenario: Ctrl/Cmd+click toggles additive selection
- GIVEN an existing non-empty selection
- WHEN an element is clicked with Ctrl/Cmd held
- THEN the system SHALL add it to the selection if absent or remove it if already selected (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:61)

#### Scenario: Box drag selects contained elements
- GIVEN a drag started from empty canvas space
- WHEN the drag rectangle fully contains one or more elements
- THEN the system SHALL select exactly those contained elements (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:100)

#### Scenario: Handles shown only for an active selection
- GIVEN the selection tool is active and one or more elements are selected
- WHEN the editor reports its handles
- THEN it SHALL expose 9 transform handles, and SHALL expose none while linear-edit or crop mode is active (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:146)

### Requirement: Move, resize, and rotate
The system SHALL move selected elements by dragging an interior point, preserving each element's offset; SHALL resize via any of the 8 handles, preserving aspect ratio when Shift is held and resizing from center when Alt is held; and SHALL rotate via the rotation handle, snapping to 15° increments when Shift is held. The system SHALL recompute element bounds, keep bound arrows following their shapes, and make every move/resize/rotate undoable (src: Sources/ExcalidrawEditor/EditorController.swift:264).

#### Scenario: Drag interior point moves the selection
- GIVEN a selected element
- WHEN an interior point is dragged by (20, 10)
- THEN the system SHALL translate the element by (20, 10) (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:61)

#### Scenario: Resize handle changes size
- GIVEN a selected element
- WHEN a resize handle is dragged to make the element 160×140
- THEN the system SHALL set the element's width to 160 and height to 140 (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:156)

#### Scenario: Rotate then undo restores the angle
- GIVEN a selected element at a known angle
- WHEN it is rotated and the operation is undone
- THEN the system SHALL restore the original angle (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:156)

### Requirement: Group and ungroup
The system SHALL group a selection by appending a shared group id to every member so they move and select as a unit, and SHALL ungroup by removing the outermost group id from each member (src: Sources/ExcalidrawEditor/EditorController+Actions.swift:14).

#### Scenario: Group members share a group id
- GIVEN two or more selected elements
- WHEN they are grouped
- THEN the system SHALL append the same new group id to each member's `groupIds` (src: Tests/ExcalidrawEditorTests/EditorActionsTests.swift:18)

#### Scenario: Ungroup removes the outermost group id
- GIVEN a grouped selection
- WHEN it is ungrouped
- THEN the system SHALL remove the outermost group id from each member (src: Tests/ExcalidrawEditorTests/EditorActionsTests.swift:96)

### Requirement: Duplicate and lock
The system SHALL duplicate the selection by creating copies offset by (10, 10) and selecting the copies, and SHALL support locking and unlocking elements such that locked elements cannot be selected or moved (src: Sources/ExcalidrawEditor/EditorController+Actions.swift:14).

#### Scenario: Duplicate offsets and selects copies
- GIVEN a selected element
- WHEN it is duplicated
- THEN the system SHALL create a copy offset by (10, 10) and make the copy the new selection (src: Tests/ExcalidrawEditorTests/EditorActionsTests.swift:18)

#### Scenario: Locked element ignores selection
- GIVEN a locked rectangle
- WHEN it is tapped with the selection tool
- THEN the system SHALL NOT add it to the selection (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:61)

### Requirement: Z-order reordering
The system SHALL reorder the selected elements relative to the others: to front (end of order), to back (start of order), forward (one position up), and backward (one position down) (src: Sources/ExcalidrawEditor/EditorController+Actions.swift:14).

#### Scenario: Bring to front moves to end of order
- GIVEN ordered elements [A, B, C] with A selected
- WHEN bring-to-front is invoked
- THEN the order SHALL become [B, C, A] (src: Tests/ExcalidrawEditorTests/EditorActionsTests.swift:18)

### Requirement: Align and flip
The system SHALL align the selected elements to the left, right, horizontal center, top, bottom, or vertical center of the selection bounds, and SHALL flip the selection horizontally or vertically about the selection-bounds center while preserving each element's styles (src: Sources/ExcalidrawEditor/EditorController+Actions.swift:14).

#### Scenario: Align left sets shared x
- GIVEN a multi-element selection whose left bound is x=0
- WHEN align-left is invoked
- THEN every selected element SHALL have x=0 (src: Tests/ExcalidrawEditorTests/EditorActionsTests.swift:18)

#### Scenario: Flip horizontal mirrors within bounds
- GIVEN a multi-element selection
- WHEN flip-horizontal is invoked
- THEN the system SHALL mirror each element's position about the selection-bounds center, preserving styles (src: Tests/ExcalidrawEditorTests/EditorActionsTests.swift:96)

### Requirement: Copy and paste
The system SHALL copy the current selection as `.excalidraw` JSON including any referenced files, and SHALL paste by regenerating element ids, offsetting positions by (+10, +10), selecting the pasted copies, and preserving all element properties (src: Sources/ExcalidrawEditor/EditorController+Commands.swift:38).

#### Scenario: Paste regenerates ids and offsets copies
- GIVEN a copied selection on the clipboard
- WHEN it is pasted
- THEN the system SHALL create copies with new ids offset by (+10, +10), select them, and preserve their properties (src: Sources/ExcalidrawEditor/EditorController+Commands.swift:38)

### Requirement: Linear point editing
The system SHALL enter linear-point editing for a line or arrow via double-tap or `beginLinearEdit`, exposing a draggable handle for each vertex plus a midpoint handle between consecutive vertices. Dragging a vertex SHALL move that point; dragging a midpoint SHALL insert a new vertex at that position. While in linear-edit mode the system SHALL suppress transform handles and box selection, and SHALL exit on tool change, click-away, or `exitLinearEdit`. All linear edits SHALL be undoable (src: Sources/ExcalidrawEditor/EditorController.swift:115).

#### Scenario: Drag a vertex moves the point
- GIVEN a 3-point line in linear-edit mode
- WHEN the middle vertex is dragged to (50, 40)
- THEN the system SHALL move that vertex to (50, 40) (src: Tests/ExcalidrawEditorTests/LinearEditTests.swift:21)

#### Scenario: Drag a midpoint inserts a vertex
- GIVEN a 3-point line in linear-edit mode
- WHEN a midpoint handle is dragged
- THEN the system SHALL insert a new vertex, producing 4 points (src: Tests/ExcalidrawEditorTests/LinearEditTests.swift:21)

#### Scenario: Tool change exits linear edit
- GIVEN a line in linear-edit mode
- WHEN the active tool is changed
- THEN the system SHALL exit linear-edit mode (src: Tests/ExcalidrawEditorTests/LinearEditTests.swift:76)

### Requirement: Image cropping
The system SHALL enter image-crop editing via `beginCropEdit(id, naturalW, naturalH)`, exposing 8 crop handles and tracking the crop as an `ImageCrop` in natural pixel coordinates. Dragging a crop handle SHALL adjust the visible viewport clamped to the full-image bounds, updating the element's position and size; the system SHALL provide a programmatic `setCrop`, SHALL exit on tool change or pointer-down away, and SHALL make crop changes undoable (src: Sources/ExcalidrawEditor/EditorController+Crop.swift:1).

#### Scenario: Begin crop exposes 8 handles
- GIVEN an image element
- WHEN crop editing begins
- THEN the system SHALL expose 8 crop handles (src: Tests/ExcalidrawEditorTests/ImageCropTests.swift:13)

#### Scenario: Drag left edge shrinks width and clamps
- GIVEN an image in crop mode
- WHEN the left edge handle is dragged inward
- THEN the system SHALL reduce the crop width and increase the crop's x, clamped to the full-image bounds (src: Tests/ExcalidrawEditorTests/ImageCropTests.swift:102)
