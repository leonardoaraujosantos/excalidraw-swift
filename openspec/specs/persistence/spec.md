# Persistence & Export

## Purpose

App-level document lifecycle for the editor: autosave that survives relaunch, a recents list, Files-app open/save, a PNG scene-embed round-trip so exported images re-open as editable drawings, and PNG/SVG export. This layer builds on the model-level serialization (file-format) and ties it into the SwiftUI editor's document and export flows.

## Requirements

### Requirement: Autosave slot
The system SHALL persist the current scene to an `Autosave.excalidraw` file in Application Support via an atomic write, only when the scene has visible elements, and SHALL support loading and clearing the slot. (src: Sources/ExcalidrawUI/DocumentStore.swift:11, Sources/ExcalidrawUI/EditorModel+Documents.swift:11)

#### Scenario: Autosave round-trips and clears
- GIVEN scene data
- WHEN it is saved to the autosave slot
- THEN it SHALL be readable back identically, and after clearing the slot SHALL load as nil (src: Tests/ExcalidrawUITests/DocumentStoreTests.swift:13)

#### Scenario: Empty scene is not autosaved
- GIVEN a scene with no visible elements
- WHEN `autosave` is called
- THEN no data SHALL be written to the autosave slot (src: Sources/ExcalidrawUI/EditorModel+Documents.swift:11)

### Requirement: Autosave restore only when empty
The system SHALL restore the autosaved drawing on launch only if the canvas is still empty, never clobbering an already-open document, wired via a SwiftUI `.task`. (src: Sources/ExcalidrawUI/EditorModel+Documents.swift:16)

#### Scenario: Fresh editor restores autosave
- GIVEN a saved autosave and a fresh empty editor
- WHEN `restoreAutosaveIfEmpty` runs
- THEN the autosaved elements SHALL be loaded (src: Tests/ExcalidrawUITests/DocumentStoreTests.swift:64)

#### Scenario: Non-empty editor is not clobbered
- GIVEN an editor that already contains elements
- WHEN `restoreAutosaveIfEmpty` runs
- THEN the existing scene SHALL remain unchanged (src: Tests/ExcalidrawUITests/DocumentStoreTests.swift:64)

### Requirement: Autosave on scene-phase change
The system SHALL autosave when the app leaves the active scene phase. (src: Sources/ExcalidrawUI/EditorView+Documents.swift:79)

#### Scenario: Leaving active phase triggers autosave
- GIVEN the editor is shown
- WHEN the SwiftUI scene phase becomes anything other than `.active`
- THEN `autosave` SHALL be invoked (src: Sources/ExcalidrawUI/EditorView+Documents.swift:79)

### Requirement: Recents list
The system SHALL maintain a recents list of at most 12 documents, freshest-first, stored as security-scoped bookmarks in `UserDefaults` under the key `excalidraw.recentDocuments`, deduplicated by `resolvingSymlinksInPath` so `/var` and `/private/var` paths canonicalise equal, dropping stale bookmarks, and clearable. (src: Sources/ExcalidrawUI/DocumentStore.swift:32)

#### Scenario: Re-adding a document dedupes and moves it to front
- GIVEN documents A then B added to recents
- WHEN A is added again
- THEN A SHALL appear once and be the freshest entry (src: Tests/ExcalidrawUITests/DocumentStoreTests.swift:21)

#### Scenario: Cap at 12 entries
- GIVEN more than 12 documents added to recents
- WHEN the recents list is read
- THEN it SHALL retain only the 12 freshest entries (src: Sources/ExcalidrawUI/DocumentStore.swift:32)

### Requirement: Open document (security-scoped)
The system SHALL open a `.excalidraw` file using start/stop security-scoped access, SHALL replace the current scene, SHALL record the URL in recents, and SHALL return a Bool indicating success; a PNG with an embedded scene SHALL also re-open. (src: Sources/ExcalidrawUI/EditorModel+Documents.swift:23)

#### Scenario: Saved document re-opens into a fresh editor
- GIVEN a scene saved to a `.excalidraw` URL
- WHEN it is opened in a fresh editor
- THEN the editor SHALL contain the saved elements and `openDocument` SHALL return true (src: Tests/ExcalidrawUITests/DocumentStoreTests.swift:52)

#### Scenario: Exported PNG with embedded scene re-opens
- GIVEN a PNG exported with an embedded scene
- WHEN it is opened via `openDocument`
- THEN the embedded scene SHALL be loaded and the URL recorded in recents (src: Tests/ExcalidrawUITests/PNGReopenTests.swift:9)

### Requirement: Save document (security-scoped)
The system SHALL write the current scene to a URL via an atomic write using start/stop security-scoped access, SHALL record the URL in recents, and SHALL return a Bool indicating success. (src: Sources/ExcalidrawUI/EditorModel+Documents.swift:40)

#### Scenario: Save writes and records
- GIVEN a scene and a target URL
- WHEN `saveDocument` is called
- THEN the document SHALL be written atomically, recorded in recents, and return true (src: Tests/ExcalidrawUITests/DocumentStoreTests.swift:52)

### Requirement: Files-app integration
The system SHALL present a `fileImporter` accepting `.excalidraw`, `.json`, and `.png` content types that routes the picked URL to `openDocument`, and a `fileExporter` that wraps the scene in a `SceneFileDocument` (`FileDocument`) defaulting the filename to "Drawing" and records the URL in recents on success. (src: Sources/ExcalidrawUI/EditorView+Documents.swift:8)

#### Scenario: Import routes to openDocument
- GIVEN the file importer is presented
- WHEN the user picks a `.excalidraw`, `.json`, or `.png` file
- THEN the picked URL SHALL be passed to `openDocument` (src: Sources/ExcalidrawUI/EditorView+Documents.swift:68)

#### Scenario: Export wraps scene and records recents
- GIVEN the file exporter is presented
- WHEN export succeeds
- THEN the scene SHALL be written via `SceneFileDocument` with default filename "Drawing" and the URL recorded in recents (src: Sources/ExcalidrawUI/EditorView+Documents.swift:39)

### Requirement: PNG export with scene embed
The system SHALL render a scene to a PNG (default 2x scale, 16pt padding), SHALL embed the scene JSON base64-encoded in a `tEXt` chunk keyed `excalidraw` inserted after `IHDR` with a valid CRC, SHALL keep the PNG a valid image, SHALL omit the embed when `embedScene` is false, and SHALL return nil for an empty scene. (src: Sources/ExcalidrawRender/Exporter.swift:23, Sources/ExcalidrawRender/PNGSceneEmbed.swift:15)

#### Scenario: Export embeds a re-openable scene
- GIVEN a scene with elements
- WHEN it is exported as PNG (default options)
- THEN the PNG SHALL contain the embedded scene and the extracted scene SHALL match the original, UTF-8 included (src: Tests/ExcalidrawRenderTests/PNGSceneEmbedTests.swift:19)

#### Scenario: Embedded PNG stays a valid image
- GIVEN a PNG exported with an embedded scene
- WHEN it is decoded as an image
- THEN it SHALL decode successfully (the tEXt chunk does not corrupt the PNG) (src: Tests/ExcalidrawRenderTests/PNGSceneEmbedTests.swift:40)

#### Scenario: embedScene false omits the scene
- GIVEN a scene exported with `embedScene: false`
- WHEN the PNG is inspected
- THEN it SHALL contain no embedded scene (src: Tests/ExcalidrawRenderTests/PNGSceneEmbedTests.swift:34)

### Requirement: PNG re-open extraction
The system SHALL extract an embedded scene from a PNG `tEXt` chunk and decode its base64 JSON back into a `Scene`, SHALL return nil when the chunk is absent or invalid, and `openSceneFromPNG` SHALL revert the active tool to selection. (src: Sources/ExcalidrawRender/PNGSceneEmbed.swift:31, Sources/ExcalidrawUI/EditorModel.swift:465)

#### Scenario: Exported PNG re-opens into a fresh editor
- GIVEN a PNG exported from a scene with one rectangle
- WHEN it is re-opened via `openSceneFromPNG`
- THEN the editor SHALL contain the rectangle and return true (src: Tests/ExcalidrawUITests/PNGReopenTests.swift:9)

#### Scenario: Non-PNG or scene-less data returns false
- GIVEN data that is not a PNG with an embedded scene
- WHEN `openSceneFromPNG` is called
- THEN it SHALL return false and leave the scene unchanged (src: Tests/ExcalidrawUITests/PNGReopenTests.swift:28)

### Requirement: SVG export
The system SHALL render a scene to an SVG string (default 16pt padding) with a background `<rect>`, a per-element `<g>` carrying transform and opacity, and `<path>`/`<text>`/`<image>` bodies, SHALL XML-escape text, SHALL emit a `rotate()` transform on rotated elements, and SHALL yield `width="0"` for an empty scene. (src: Sources/ExcalidrawRender/SVGExporter.swift:13)

#### Scenario: Empty scene yields zero-size SVG
- GIVEN an empty scene
- WHEN it is exported to SVG
- THEN the output SHALL be an `<svg>` with `width="0"` (src: Tests/ExcalidrawRenderTests/SVGExportTests.swift:12)

#### Scenario: Shape emits sized SVG with a path
- GIVEN a 100x60 rectangle exported with 10pt padding
- WHEN it is rendered
- THEN the SVG SHALL be 120x80 and contain a `<path>` with the element's stroke colour (src: Tests/ExcalidrawRenderTests/SVGExportTests.swift:18)

#### Scenario: Text is emitted and XML-escaped
- GIVEN a text element containing `<` and `>`
- WHEN it is rendered to SVG
- THEN it SHALL emit a `<text>` element with the characters XML-escaped (src: Tests/ExcalidrawRenderTests/SVGExportTests.swift:36)

#### Scenario: Rotated element gets a rotate transform
- GIVEN an element with a non-zero angle
- WHEN it is rendered to SVG
- THEN its `<g>` transform SHALL include `rotate(` (src: Tests/ExcalidrawRenderTests/SVGExportTests.swift:44)

### Requirement: No DocumentGroup browser
The system SHALL NOT present a `DocumentGroup` document picker on launch; instead it SHALL launch directly into a single blank or autosaved `EditorView`, with document access provided through the manual Open… button and the recents list. (src: App/ExcalidrawApp.swift:12)

#### Scenario: App launches into the editor
- GIVEN the app starts
- WHEN the root window appears
- THEN it SHALL show an `EditorView` rather than a document browser (src: App/ExcalidrawApp.swift:12)

#### Scenario: Document access is manual
- GIVEN the editor is shown
- WHEN the user wants to open a document
- THEN access SHALL be via the Open… button and recents, not a document picker (src: Sources/ExcalidrawUI/EditorView+Documents.swift:8)
