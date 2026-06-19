# File Format

## Purpose

Model-level serialization that keeps `.excalidraw` scene documents and `.excalidrawlib` libraries wire-compatible with excalidraw.com. It defines how scenes and libraries are encoded to and decoded from JSON bytes, how the document envelope is shaped, how binary image assets are stored, and how legacy or partial payloads are canonicalised on load so the Swift port reads and writes the same files as the upstream web app.

## Requirements

### Requirement: .excalidraw JSON round-trip
The system SHALL encode a `Scene` to `.excalidraw` JSON bytes with stable sorted keys and optional pretty printing, SHALL pass every decode through `Restore` canonicalisation, and SHALL guarantee that encode→decode→encode is a fixed point preserving model equality, including UTF-8 content. (src: Sources/ExcalidrawModel/SceneDocument.swift:6, Sources/ExcalidrawModel/Persistence.swift:10)

#### Scenario: Encode produces stable, optionally pretty JSON
- GIVEN a `Scene`
- WHEN it is encoded via `SceneDocument.encode`
- THEN the JSON SHALL be emitted with `sortedKeys` for diff stability and with `prettyPrinted` controllable by the caller (default true) (src: Sources/ExcalidrawModel/Persistence.swift:10)

#### Scenario: Decode canonicalises through Restore
- GIVEN raw `.excalidraw` bytes
- WHEN they are decoded via `SceneDocument.decode`
- THEN the decoder SHALL run the file through `Restore.restore` before building the `Scene` (src: Sources/ExcalidrawModel/SceneDocument.swift:16)

#### Scenario: Re-encode is a fixed point preserving equality
- GIVEN a minimal scene file decoded into `ExcalidrawFile` A
- WHEN A is re-encoded and decoded into `ExcalidrawFile` B
- THEN A SHALL equal B and the re-encoded JSON SHALL be semantically equal to the source (no fields dropped or altered) (src: Tests/ExcalidrawModelTests/RoundTripTests.swift:5)

### Requirement: Document envelope
The system SHALL wrap a scene in a top-level envelope carrying `type` (`"excalidraw"`), `version` (schema version 2), `source` metadata, an `elements` array, an `appState` key-value bag that preserves unmodelled keys, and a `files` binary image store, and SHALL restore the envelope to the current schema version on load. (src: Sources/ExcalidrawModel/ExcalidrawFile.swift:58, Sources/ExcalidrawModel/ElementType.swift:25, Sources/ExcalidrawModel/Restore.swift:9)

#### Scenario: Envelope fields are present
- GIVEN a decoded `.excalidraw` document
- THEN it SHALL expose `type`, `version`, `source`, `elements`, `appState`, and `files` (src: Sources/ExcalidrawModel/ExcalidrawFile.swift:58)

#### Scenario: AppState preserves unmodelled keys
- GIVEN an `appState` containing keys the model does not interpret
- WHEN it is encoded and decoded
- THEN the unknown keys SHALL reappear unchanged while typed accessors expose known keys (src: Tests/ExcalidrawModelTests/RestoreAndSceneTests.swift:61)

#### Scenario: Restore upgrades type and version
- GIVEN a file whose `type` differs and whose `version` is below 2
- WHEN it is restored
- THEN its `type` SHALL become `"excalidraw"` and its `version` SHALL become 2 (src: Tests/ExcalidrawModelTests/RestoreAndSceneTests.swift:33)

### Requirement: Binary file storage
The system SHALL store each referenced image as a `BinaryFileData` record carrying `mimeType`, `id`, `dataURL` (base64 data URL), a `created` timestamp, an optional `lastRetrieved`, and an optional `version`, keyed by file id in the envelope `files` map. (src: Sources/ExcalidrawModel/ExcalidrawFile.swift:3)

#### Scenario: Image binary round-trips its fields
- GIVEN an image referenced by an element and stored in `files`
- WHEN the document is encoded and decoded
- THEN the binary's `mimeType`, `id`, `dataURL`, `created`, `lastRetrieved`, and `version` SHALL be preserved (src: Sources/ExcalidrawModel/ExcalidrawFile.swift:3)

### Requirement: Lenient legacy loading
The system SHALL accept `.excalidraw` files from earlier schema versions and with partial payloads, substituting defaults for missing envelope keys and canonicalising the result without failing the load. (src: Sources/ExcalidrawModel/Restore.swift:1)

#### Scenario: Missing envelope keys default rather than fail
- GIVEN a `.excalidraw` file omitting `type`, `version`, `source`, `elements`, `appState`, or `files`
- WHEN it is decoded
- THEN the missing keys SHALL take default values and the load SHALL succeed (src: Sources/ExcalidrawModel/ExcalidrawFile.swift:82)

#### Scenario: Missing element indices are assigned on restore
- GIVEN a loaded file whose elements lack `index` values
- WHEN it is restored
- THEN each element SHALL receive a fractional index that sorts in document order, while existing indices are preserved (src: Tests/ExcalidrawModelTests/RestoreAndSceneTests.swift:12)

#### Scenario: Duplicate element ids are healed on restore
- GIVEN a loaded file containing two elements that share the same `id` (e.g. a
  document corrupted by an earlier id-collision before that bug was fixed)
- WHEN it is restored
- THEN the first occurrence SHALL keep its id and each later twin SHALL be
  reassigned a fresh unique id, so every element stays individually
  addressable/selectable/deletable (src: Sources/ExcalidrawModel/Restore.swift, Tests/ExcalidrawModelTests/RestoreAndSceneTests.swift)

### Requirement: .excalidrawlib library format
The system SHALL encode and decode `.excalidrawlib` libraries, SHALL read both the V1 (flat/legacy `library: [[element, ...], ...]`) and V2 (`"type":"excalidrawlib"`, `libraryItems` with `id`/`status`/`created`/`name`/`elements`) shapes, SHALL write V2, and SHALL handle empty libraries. (src: Sources/ExcalidrawModel/ExcalidrawLibrary.swift:1, Sources/ExcalidrawModel/LibraryStore.swift:22)

#### Scenario: Reads a V1 (legacy) library
- GIVEN a V1 `.excalidrawlib` fixture using the flat `library` array
- WHEN it is decoded
- THEN its items SHALL be loaded non-empty (src: Tests/ExcalidrawModelTests/ExcalidrawLibraryTests.swift:5)

#### Scenario: Encodes as V2 and round-trips
- GIVEN a library of element groups
- WHEN it is encoded and decoded
- THEN the output SHALL declare `"type":"excalidrawlib"` with `libraryItems`, and the decoded items SHALL match the originals (src: Tests/ExcalidrawModelTests/ExcalidrawLibraryTests.swift:12)

#### Scenario: Empty library handled
- GIVEN a V2 payload `{"type":"excalidrawlib","version":2}` with no items
- WHEN it is decoded
- THEN the library SHALL be empty without error (src: Tests/ExcalidrawModelTests/ExcalidrawLibraryTests.swift:27)

### Requirement: Library persistent store
The system SHALL load library items from a default `library.excalidrawlib` file in Application Support on initialisation, SHALL persist items to disk after each mutation, SHALL accept a custom store URL for testing, and SHALL return an empty array when the file is absent. (src: Sources/ExcalidrawModel/LibraryStore.swift:13)

#### Scenario: Missing file loads as empty
- GIVEN a store URL whose file does not exist
- WHEN `load` is called
- THEN it SHALL return an empty array (src: Tests/ExcalidrawModelTests/LibraryStoreTests.swift:17)

#### Scenario: Save then load round-trips and creates the directory
- GIVEN a store at a temp URL
- WHEN items are saved
- THEN the parent directory SHALL be created and a subsequent `load` SHALL return the saved items; a later save of an empty array SHALL overwrite it to empty (src: Tests/ExcalidrawModelTests/LibraryStoreTests.swift:21)

#### Scenario: Default store path
- GIVEN the default store
- THEN its URL SHALL end with `library.excalidrawlib` (src: Tests/ExcalidrawModelTests/LibraryStoreTests.swift:36)
