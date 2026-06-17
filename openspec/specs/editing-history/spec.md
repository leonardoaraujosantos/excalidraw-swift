# Editing History

## Purpose

Undo and redo are implemented with diff-based deltas over scene snapshots: each edit is recorded as the set of elements that actually changed, with a reversible inverse for undo. A transactional store ties the scene to its history, committing the net change of a transaction as a single undo step and supporting live (uncommitted) interaction updates such as drag and resize.

## Requirements

### Requirement: Element change tracking
The system SHALL represent the change to a single element as a before/after pair of whole-element snapshots, where a `nil` before means the element was inserted and a `nil` after means it was removed. (src: Sources/ExcalidrawModel/History.swift:1)

#### Scenario: Insertion has no before snapshot
- GIVEN an element that did not exist in the prior state
- WHEN its change is recorded
- THEN the change SHALL have a `nil` before and the new element as after (src: Sources/ExcalidrawModel/History.swift:6)

#### Scenario: Removal has no after snapshot
- GIVEN an element present in the prior state but absent in the new state
- WHEN its change is recorded
- THEN the change SHALL have the prior element as before and a `nil` after (src: Sources/ExcalidrawModel/History.swift:6)

### Requirement: Scene delta diff and inverse
The system SHALL compute a scene delta between two element lists keyed by element id, recording only elements that actually changed, and SHALL produce an inverse delta that swaps each change's before and after for undo. (src: Sources/ExcalidrawModel/History.swift:34)

#### Scenario: Delta records only changed elements
- GIVEN an old and a new element list where only some elements differ
- WHEN the delta between them is computed
- THEN the delta SHALL contain entries only for the elements that changed (src: Sources/ExcalidrawModel/History.swift:34)

#### Scenario: Inverse swaps before and after
- GIVEN a scene delta
- WHEN its inverse is computed
- THEN each change SHALL have its before and after swapped (src: Sources/ExcalidrawModel/History.swift:45)

### Requirement: Undo and redo stacks
The system SHALL maintain separate undo and redo stacks of recorded deltas, and recording a new change SHALL clear the redo stack so a fresh edit branches history. (src: Sources/ExcalidrawModel/History.swift:51)

#### Scenario: New edit clears the redo stack
- GIVEN a history with deltas available to redo
- WHEN a new change is recorded
- THEN the redo stack SHALL be emptied (src: Sources/ExcalidrawModel/History.swift:66)

#### Scenario: Undo moves a delta to the redo stack
- GIVEN a history with at least one undoable delta
- WHEN the most recent delta is popped for undo
- THEN it SHALL be returned and pushed onto the redo stack (src: Sources/ExcalidrawModel/History.swift:73)

### Requirement: Transactional store
The system SHALL provide a store that ties a scene to its history, committing the net change of a transaction as one undo step, supporting live interaction updates that modify the scene without recording history until committed, and applying the inverse delta on undo and the delta on redo. (src: Sources/ExcalidrawModel/History.swift:89)

#### Scenario: Create then undo empties the scene
- GIVEN an empty scene and the rectangle tool
- WHEN a rectangle is created by drag and then undone
- THEN the scene SHALL have no visible elements (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:207)

#### Scenario: Move then undo restores the position
- GIVEN a selected element moved by a drag
- WHEN the move is undone
- THEN the element SHALL return to its original position (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:61)

#### Scenario: Redo re-applies an undone edit
- GIVEN an element creation that was undone leaving an empty scene
- WHEN the edit is redone
- THEN the scene SHALL again contain one visible element (src: Tests/ExcalidrawEditorTests/EditorControllerTests.swift:207)

#### Scenario: No redo after a new edit
- GIVEN an undone edit available to redo
- WHEN a new edit is committed
- THEN the redo SHALL no longer be available (src: Sources/ExcalidrawModel/History.swift:66)
