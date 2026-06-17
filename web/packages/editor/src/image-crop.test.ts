import { Point } from "@xs/math";
import { type ExcalidrawElement, type ImageCrop, Scene, defaultBase } from "@xs/model";
import { describe, expect, it } from "vitest";
import { EditorController } from "./controller.js";
import { pointerEvent } from "./pointer-event.js";

function imageEditor(): EditorController {
  const el: ExcalidrawElement = {
    ...defaultBase("img", { width: 100, height: 100 }),
    type: "image",
    fileId: "f",
    status: "saved",
    scale: [1, 1],
    crop: null,
  };
  return new EditorController(new Scene([el]));
}

function imageCrop(ec: EditorController): ImageCrop | null {
  const el = ec.scene.element("img");
  return el?.type === "image" ? el.crop : null;
}

describe("image crop — setCrop", () => {
  it("set and clear a crop", () => {
    const ec = imageEditor();
    const crop: ImageCrop = {
      x: 10,
      y: 20,
      width: 50,
      height: 40,
      naturalWidth: 100,
      naturalHeight: 100,
    };
    ec.setCrop("img", crop);
    expect(imageCrop(ec)).toEqual(crop);
    ec.setCrop("img", null);
    expect(imageCrop(ec)).toBeNull();
  });

  it("crop is undoable", () => {
    const ec = imageEditor();
    ec.setCrop("img", { x: 5, y: 5, width: 20, height: 20, naturalWidth: 100, naturalHeight: 100 });
    expect(ec.undo()).toBe(true);
    expect(imageCrop(ec)).toBeNull();
  });

  it("setCrop ignores a non-image", () => {
    const ec = new EditorController(new Scene([{ ...defaultBase("r"), type: "rectangle" }]));
    ec.setCrop("r", { x: 0, y: 0, width: 1, height: 1, naturalWidth: 1, naturalHeight: 1 });
    expect(ec.canUndo).toBe(false);
  });
});

describe("interactive crop mode", () => {
  it("rejects a non-image", () => {
    const ec = new EditorController(new Scene([{ ...defaultBase("r"), type: "rectangle" }]));
    expect(ec.beginCropEdit("r", 100, 100)).toBe(false);
    expect(ec.editingCropID).toBeNull();
  });

  it("enters mode with eight handles", () => {
    const ec = imageEditor();
    expect(ec.beginCropEdit("img", 200, 200)).toBe(true);
    expect(ec.editingCropID).toBe("img");
    expect([...ec.selectedIDs]).toEqual(["img"]);
    expect(ec.cropEditHandles()?.length).toBe(8);
    expect(ec.transformHandles().size).toBe(0);
  });

  it("dragging a handle crops the image", () => {
    const ec = imageEditor();
    ec.beginCropEdit("img", 200, 200);
    ec.pointerDown(pointerEvent(new Point(0, 50), "down"));
    ec.pointerMove(pointerEvent(new Point(10, 50), "move"));
    ec.pointerUp(pointerEvent(new Point(10, 50), "up"));
    const el = ec.scene.element("img")!;
    expect(el.x).toBeCloseTo(10, 9);
    expect(el.width).toBeCloseTo(90, 9);
    const crop = imageCrop(ec)!;
    expect(crop.x).toBeCloseTo(20, 9);
    expect(crop.width).toBeCloseTo(180, 9);
    expect(ec.canUndo).toBe(true);
  });

  it("crop drag clamps to image bounds", () => {
    const ec = imageEditor();
    ec.beginCropEdit("img", 200, 200);
    ec.pointerDown(pointerEvent(new Point(0, 50), "down"));
    ec.pointerMove(pointerEvent(new Point(-100, 50), "move"));
    expect(ec.scene.element("img")?.x ?? -1).toBeGreaterThanOrEqual(0);
  });

  it("tapping away from a handle exits crop mode", () => {
    const ec = imageEditor();
    ec.beginCropEdit("img", 200, 200);
    ec.pointerDown(pointerEvent(new Point(500, 500), "down"));
    expect(ec.editingCropID).toBeNull();
  });

  it("changing tool exits crop mode", () => {
    const ec = imageEditor();
    ec.beginCropEdit("img", 200, 200);
    ec.setTool("rectangle");
    expect(ec.editingCropID).toBeNull();
  });
});
