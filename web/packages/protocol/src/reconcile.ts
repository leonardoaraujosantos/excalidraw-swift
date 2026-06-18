import type { ExcalidrawElement } from "@cyberdynecorp/excalidraw-model";

/**
 * Decide whether a `remote` element should replace the `local` one with the
 * same id. This is Excalidraw's last-writer-wins rule, reused unchanged on both
 * the web and Swift clients so they converge bit-for-bit:
 *
 *   1. higher `version` wins;
 *   2. on equal `version`, the lower `versionNonce` wins.
 *
 * The rule is a total order on `(version desc, versionNonce asc)`, so it is
 * **symmetric**: whichever side a peer holds locally, both peers pick the same
 * winner — no central authority or CRDT needed. Soft-deletes (`isDeleted`) carry
 * a bumped version like any other edit, so deletion races resolve the same way.
 */
export function preferRemote(local: ExcalidrawElement, remote: ExcalidrawElement): boolean {
  if (remote.version !== local.version) return remote.version > local.version;
  return remote.versionNonce < local.versionNonce;
}

/** The winning element of a same-id pair (the local one on an exact tie). */
export function reconcileElement(
  local: ExcalidrawElement,
  remote: ExcalidrawElement,
): ExcalidrawElement {
  return preferRemote(local, remote) ? remote : local;
}

/**
 * Merge a batch of `remote` elements into the `local` set by id, applying
 * {@link reconcileElement} per id. Existing local order is preserved (winners
 * substituted in place); elements present only in `remote` are appended in the
 * order received. Callers that need canonical stacking re-sort the result by
 * fractional index afterwards.
 */
export function reconcileElements(
  local: readonly ExcalidrawElement[],
  remote: readonly ExcalidrawElement[],
): ExcalidrawElement[] {
  const remoteById = new Map(remote.map((el) => [el.id, el] as const));
  const seen = new Set<string>();
  const merged: ExcalidrawElement[] = [];

  for (const localEl of local) {
    const remoteEl = remoteById.get(localEl.id);
    merged.push(remoteEl === undefined ? localEl : reconcileElement(localEl, remoteEl));
    seen.add(localEl.id);
  }
  for (const remoteEl of remote) {
    if (!seen.has(remoteEl.id)) {
      merged.push(remoteEl);
      seen.add(remoteEl.id);
    }
  }
  return merged;
}

/**
 * Given the elements a peer already has and an incoming batch, return only the
 * elements that actually changed (new id, or the remote version won). Lets a
 * client apply a minimal update and skip a redundant repaint when nothing won.
 */
export function changedByReconcile(
  local: readonly ExcalidrawElement[],
  remote: readonly ExcalidrawElement[],
): ExcalidrawElement[] {
  const localById = new Map(local.map((el) => [el.id, el] as const));
  const changed: ExcalidrawElement[] = [];
  for (const remoteEl of remote) {
    const localEl = localById.get(remoteEl.id);
    if (localEl === undefined || preferRemote(localEl, remoteEl)) changed.push(remoteEl);
  }
  return changed;
}
