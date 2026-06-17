# Diagram Generators

## Purpose

Procedural generators that turn structured input or a single command into a group of ready-to-edit drawing elements. They cover Mermaid flowchart parsing, tabular grids, sticky notes, and bar/line charts. Every generator produces grouped, undoable elements positioned at the insertion point and leaves the generated elements selected.

## Requirements

### Requirement: Mermaid flowchart parser
The system SHALL parse a Mermaid flowchart/graph with TD/TB/BT/LR/RL direction, recognizing node shapes [rect] (rounded), {diamond}, ((ellipse)), and ([stadium]) and edges --> --- -.-> ==> with optional |labels|, SHALL emit shapes with bound-text labels and bound arrows using correct arrowheads (dashed for -.->), SHALL auto-layer by direction using longest-path layout, SHALL position the result so its top-left is at the insertion point and select all generated elements, and SHALL return nil for non-Mermaid text (src: Sources/ExcalidrawEditor/MermaidParser.swift:1, Sources/ExcalidrawEditor/EditorController+Mermaid.swift:1).

#### Scenario: Three-node flowchart generates shapes, texts, and arrows
- GIVEN Mermaid text describing 3 nodes connected by 2 edges
- WHEN it is parsed and generated
- THEN the system SHALL produce 3 shapes, 3 bound texts, and 2 bound arrows (src: Tests/ExcalidrawEditorTests/MermaidParserTests.swift:7)

#### Scenario: Bracket syntax maps to shape kind
- GIVEN nodes declared with different bracket syntaxes
- WHEN they are parsed
- THEN each node SHALL map to its corresponding shape kind (src: Tests/ExcalidrawEditorTests/MermaidParserTests.swift:40)

#### Scenario: Plain link has no arrowhead and dotted binds both ends
- GIVEN edges using `---` and `-.->`
- WHEN they are parsed
- THEN `---` SHALL have no arrowhead and the generated arrows SHALL bind both ends (src: Tests/ExcalidrawEditorTests/MermaidParserTests.swift:73)

#### Scenario: Non-Mermaid text returns nil
- GIVEN text that is not a Mermaid flowchart
- WHEN parsing is attempted
- THEN the system SHALL return nil (src: Sources/ExcalidrawEditor/MermaidParser.swift:1)

### Requirement: Tables
The system SHALL create a rows×cols grid of transparent rectangle cells with bound-text labels that share a single group id and carry table metadata in customData["table"], SHALL support adding a row (one cell per column) and adding a column (one cell per row), SHALL resolve a cell edit target via boundTextHit, and SHALL make these operations undoable (src: Sources/ExcalidrawEditor/EditorController+Table.swift:8).

#### Scenario: Two-by-three table produces twelve elements
- GIVEN a request for a 2×3 table
- WHEN it is created
- THEN the system SHALL produce 12 elements (cells plus bound texts) (src: Tests/ExcalidrawEditorTests/TableTests.swift:11)

#### Scenario: Add row and add column grow the grid
- GIVEN an existing 2×3 table
- WHEN a row is added and then a column is added
- THEN the system SHALL add 3 elements for the row and 2 elements for the column (src: Tests/ExcalidrawEditorTests/TableTests.swift:40)

#### Scenario: Cell hit resolves container and text ids
- GIVEN a table cell location
- WHEN boundTextHit is queried
- THEN the system SHALL return the container and bound-text element ids (src: Tests/ExcalidrawEditorTests/TableTests.swift:62)

### Requirement: Sticky notes
The system SHALL create a 160×160 rounded filled rectangle (default yellow or a custom color) with a centered bound text whose autoResize is false, grouped together, SHALL return the container and text ids for editing, SHALL allow editing the label via double-tap/boundTextHit, and SHALL make the operation undoable (src: Sources/ExcalidrawEditor/EditorController+StickyNote.swift:1).

#### Scenario: Sticky note returns container and text ids
- GIVEN a request to create a sticky note
- WHEN it is created
- THEN the system SHALL produce a grouped container and centered bound text and return both ids (src: Tests/ExcalidrawEditorTests/TableTests.swift:47)

### Requirement: Charts
The system SHALL create a bar or line chart from numeric values scaled to the maximum value, with a baseline axis and optional category labels below the columns, SHALL group all chart elements, SHALL record the kind and values in customData, SHALL use the current item's background color, and SHALL make the operation undoable (src: Sources/ExcalidrawEditor/EditorController+Chart.swift:1).

#### Scenario: Bar chart produces grouped rects and a baseline
- GIVEN numeric values and the bar kind
- WHEN a chart is created
- THEN the system SHALL produce bar rectangles and a baseline grouped together (src: Sources/ExcalidrawEditor/EditorController+Chart.swift:1)

#### Scenario: Line chart produces a polyline and a baseline
- GIVEN numeric values and the line kind
- WHEN a chart is created
- THEN the system SHALL produce a polyline and a baseline grouped together (src: Sources/ExcalidrawEditor/EditorController+Chart.swift:1)
