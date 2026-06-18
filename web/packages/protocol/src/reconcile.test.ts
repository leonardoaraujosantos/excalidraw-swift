import { type ExcalidrawElement, defaultBase } from "@cyberdynecorp/excalidraw-model";
import { describe, expect, it } from "vitest";
import {
  changedByReconcile,
  preferRemote,
  reconcileElement,
  reconcileElements,
} from "./reconcile.js";

function el(
  id: string,
  version: number,
  versionNonce: number,
  extra: { isDeleted?: boolean } = {},
): ExcalidrawElement {
  return { ...defaultBase(id, {}), type: "rectangle", version, versionNonce, ...extra };
}

describe("reconcileElement", () => {
  it("the higher version wins", () => {
    const local = el("a", 1, 100);
    const remote = el("a", 2, 5);
    expect(reconcileElement(local, remote)).toBe(remote);
    expect(reconcileElement(remote, local)).toBe(remote);
  });

  it("keeps the local element when it is newer", () => {
    const local = el("a", 3, 100);
    const remote = el("a", 2, 5);
    expect(reconcileElement(local, remote)).toBe(local);
  });

  it("breaks a version tie by the lower versionNonce", () => {
    const local = el("a", 4, 200);
    const remote = el("a", 4, 50);
    expect(preferRemote(local, remote)).toBe(true);
    expect(reconcileElement(local, remote)).toBe(remote);
  });

  it("is symmetric — both peers converge on the same winner regardless of side", () => {
    const x = el("a", 4, 50);
    const y = el("a", 4, 200);
    // Peer 1 holds x locally and receives y; peer 2 holds y and receives x.
    const peer1 = reconcileElement(x, y);
    const peer2 = reconcileElement(y, x);
    expect(peer1.versionNonce).toBe(peer2.versionNonce);
    expect(peer1.versionNonce).toBe(50);
  });

  it("resolves a delete race by version like any other edit", () => {
    const live = el("a", 5, 10, { isDeleted: false });
    const deleted = el("a", 6, 99, { isDeleted: true });
    expect(reconcileElement(live, deleted).isDeleted).toBe(true);
  });
});

describe("reconcileElements", () => {
  it("merges: keeps local-only, appends remote-only, resolves conflicts", () => {
    const local = [el("a", 2, 1), el("b", 1, 1)];
    const remote = [el("a", 3, 1), el("c", 1, 1)];
    const merged = reconcileElements(local, remote);
    expect(merged.map((e) => e.id)).toEqual(["a", "b", "c"]); // local order, then new
    expect(merged.find((e) => e.id === "a")?.version).toBe(3); // remote 'a' won
  });

  it("preserves local order and substitutes winners in place", () => {
    const local = [el("a", 1, 1), el("b", 1, 1), el("c", 1, 1)];
    const remote = [el("b", 9, 1)];
    const merged = reconcileElements(local, remote);
    expect(merged.map((e) => e.id)).toEqual(["a", "b", "c"]);
    expect(merged[1]?.version).toBe(9);
  });

  it("converges when applied in either direction", () => {
    const a = [el("x", 1, 5), el("y", 2, 9)];
    const b = [el("x", 2, 3), el("y", 1, 4)];
    const ab = reconcileElements(a, b).sort((p, q) => p.id.localeCompare(q.id));
    const ba = reconcileElements(b, a).sort((p, q) => p.id.localeCompare(q.id));
    expect(ab.map((e) => [e.id, e.version, e.versionNonce])).toEqual(
      ba.map((e) => [e.id, e.version, e.versionNonce]),
    );
  });
});

describe("changedByReconcile", () => {
  it("returns only new ids and remote winners", () => {
    const local = [el("a", 2, 1), el("b", 5, 1)];
    const remote = [el("a", 3, 1), el("b", 1, 1), el("c", 1, 1)];
    const changed = changedByReconcile(local, remote)
      .map((e) => e.id)
      .sort();
    expect(changed).toEqual(["a", "c"]); // 'a' won, 'c' is new; 'b' local stays
  });

  it("is empty when nothing remote wins", () => {
    const local = [el("a", 9, 1)];
    const remote = [el("a", 2, 1)];
    expect(changedByReconcile(local, remote)).toEqual([]);
  });
});
