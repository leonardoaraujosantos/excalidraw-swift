# Data Model

## Purpose

The in-memory and on-disk representation of a drawing: elements, scene, app state, and the document envelope. This is the source of truth that every other capability reads and mutates, and it is kept wire-compatible with excalidraw.com.

## Requirements

### Requirement: Element representation
The system SHALL represent each drawing element as a flat object carrying a `type` discriminator plus base properties shared by all elements: `id`, position (`x`, `y`), size (`width`, `height`), `angle` (radians), stroke/fill styling, visual properties, versioning, and grouping/containment metadata.

The system SHALL support these element types: selection, rectangle, diamond, ellipse, text, freedraw, line, arrow, image, frame, magicframe, embeddable, and iframe (src: Sources/ExcalidrawModel/ElementKind.swift:7).

#### Scenario: Base properties on every element
- GIVEN any element type
- THEN it SHALL expose `id`, `x`, `y`, `width`, `height`, `angle`, `strokeColor`, `backgroundColor`, `fillStyle`, `strokeWidth`, `strokeStyle`, `roughness`, `opacity`, `seed`, `version`, `versionNonce`, `updated`, `isDeleted`, `groupIds`, `frameId`, `index`, `link`, and `locked` (src: Sources/ExcalidrawModel/BaseProperties.swift:10)

#### Scenario: Unknown element type rejected
- GIVEN JSON whose element `type` is not a known type
- WHEN it is decoded
- THEN decoding SHALL throw an error (src: Tests/ExcalidrawModelTests/ElementCodingTests.swift:88)

### Requirement: Type-specific element fields
The system SHALL carry type-specific fields alongside the base properties: text elements carry `fontSize`, `fontFamily`, `text`, `textAlign`, `verticalAlign`, `containerId`, `originalText`, `autoResize`, and `lineHeight`; freedraw carries `points`, `pressures`, and `simulatePressure`; line/arrow carry `points`, `startBinding`, `endBinding`, `startArrowhead`, `endArrowhead`, and `polygon`; arrows additionally carry `elbowed`, `fixedSegments`, `startIsSpecial`, and `endIsSpecial`; images carry `fileId`, `status`, `scale`, and `crop`; frames carry an optional `name` (src: Sources/ExcalidrawModel/ElementKind.swift:42).

#### Scenario: Text element round-trips its fields
- GIVEN a text element with font, alignment, and container binding
- WHEN it is encoded and decoded
- THEN all text-specific fields SHALL be preserved (src: Tests/ExcalidrawModelTests/ElementCodingTests.swift:44)

### Requirement: Flat JSON coding compatible with .excalidraw
The system SHALL encode and decode elements as flat JSON objects matching the `.excalidraw` format, where type-specific fields coexist with base properties at the same level (src: Sources/ExcalidrawModel/ElementCodingKeys.swift:1).

The system SHALL decode leniently, substituting sensible defaults for missing keys so that older or partial files still load (src: Sources/ExcalidrawModel/BaseProperties.swift:96).

#### Scenario: Missing keys fall back to defaults
- GIVEN a `.excalidraw` file produced by an older schema that omits some keys
- WHEN it is decoded
- THEN the missing keys SHALL take default values rather than failing the load (src: Sources/ExcalidrawModel/Restore.swift:9)

### Requirement: Grouping and containment metadata
The system SHALL allow an element to belong to multiple groups via an ordered `groupIds` array, and to be contained in a frame via `frameId` (src: Sources/ExcalidrawModel/BaseProperties.swift:30).

#### Scenario: Group membership round-trips
- GIVEN an element with `groupIds`
- WHEN it is encoded and decoded
- THEN the group membership SHALL be preserved (src: Tests/ExcalidrawModelTests/ElementCodingTests.swift:81)

### Requirement: Arrow and bound-element references
The system SHALL model arrow-to-shape binding as a `FixedPointBinding` storing the target `elementId`, a fixed-point ratio in [0,1] on each axis, and a containment `mode` (inside/orbit/skip), and SHALL list text/arrow attachments on a shape via a `boundElements` array of `{id, type}` (src: Sources/ExcalidrawModel/ValueTypes.swift:27).

#### Scenario: Binding survives shape movement
- GIVEN an arrow bound to a shape by fixed-point ratio
- WHEN the shape moves
- THEN the binding SHALL resolve to the corresponding scene point on the moved shape (src: Sources/ExcalidrawModel/ValueTypes.swift:27)

### Requirement: Lossless preservation of unmodelled data
The system SHALL preserve arbitrary unmodelled JSON via a `customData` field and an `AppState` key-value bag, using a `JSONValue` enum (null/bool/number/string/array/object), so unknown data round-trips without loss (src: Sources/ExcalidrawModel/ValueTypes.swift:78).

#### Scenario: Unknown fields survive a round-trip
- GIVEN a scene containing element `customData` and app-state keys the model does not interpret
- WHEN it is encoded and decoded
- THEN those fields SHALL reappear unchanged (src: Tests/ExcalidrawModelTests/RoundTripTests.swift:5)

### Requirement: Scene model with indexed access
The system SHALL maintain an in-memory scene as an ordered element list with an id→index map for O(1) lookup, SHALL expose visible (non-deleted) elements, and SHALL support add, replace, reorder, and soft-delete operations that keep the index consistent (src: Sources/ExcalidrawModel/Scene.swift:6).

#### Scenario: Visible elements exclude soft-deleted
- GIVEN a scene where an element has `isDeleted` set
- WHEN visible elements are requested
- THEN the deleted element SHALL be excluded (src: Sources/ExcalidrawModel/Scene.swift:37)

### Requirement: Versioned mutation
The system SHALL provide a `mutate` operation that applies a change to an element and auto-increments `version`, assigns a new `versionNonce`, and updates the `updated` timestamp, mirroring upstream reconciliation (src: Sources/ExcalidrawModel/Scene.swift:49).

#### Scenario: Mutation bumps the version
- GIVEN an element at version N
- WHEN it is mutated
- THEN its version SHALL become greater than N and its `versionNonce` SHALL change (src: Sources/ExcalidrawModel/Scene.swift:49)

### Requirement: Fractional indexing
The system SHALL assign any missing `index` using a fractional-index scheme producing base-36 keys that sort lexicographically, so z-order is stable and insertions need no full renumber (src: Sources/ExcalidrawModel/Restore.swift:33).

#### Scenario: Elements without an index get sortable keys
- GIVEN a loaded scene whose elements lack `index` values
- WHEN it is restored
- THEN each element SHALL receive a fractional index key whose lexical order matches document order (src: Sources/ExcalidrawModel/Restore.swift:33)
