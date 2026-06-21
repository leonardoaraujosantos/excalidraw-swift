// `ExcalidrawUI`'s public API vends `Tool` from `ExcalidrawEditor` (via
// `EditorModel.activeTool` / `select(tool:)`). Re-export it so embedders that
// build their own chrome on top of `EditorView(model:showsChrome:)` can name the
// type via `import ExcalidrawUI` alone, without depending on `ExcalidrawEditor`.
@_exported import enum ExcalidrawEditor.Tool
