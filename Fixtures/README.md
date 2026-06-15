# Test fixtures

Sample files used by round-trip / restore / library tests.

- `minimal_scene.excalidraw` — hand-authored v2 scene (rectangle + text) for the
  Phase 1 `.excalidraw` round-trip tests.
- `fixture_library.excalidrawlib` — copied from upstream
  (`packages/excalidraw/tests/fixtures/`) for `.excalidrawlib` parsing tests.

As the model lands (Phase 1), expand this corpus with: older schema versions,
all element types, bound text/arrows, frames, and real exports from
excalidraw.com to lock down interop fidelity.
