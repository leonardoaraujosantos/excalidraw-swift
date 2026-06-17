export { BoundingBox } from "./bounding-box.js";
export {
  type AbsoluteCoords,
  type Outline,
  LINE_CONFIRM_THRESHOLD,
  absoluteCoords,
  bounds,
  commonBounds,
  isPathALoop,
  scenePoints,
  unrotatedOutline,
} from "./element-geometry.js";
export {
  type Heading,
  Heading as Headings,
  flippedHeading,
  headingFromBoxToward,
  headingFromPoint,
  headingFromVector,
  headingVector,
  isHorizontal,
  isVertical,
} from "./heading.js";
export { cullVisible } from "./culling.js";
export { dirtyRegion } from "./dirty-region.js";
export { frameChildren, frameContaining, isFrame } from "./frames.js";
export {
  BINDING_DISTANCE,
  bindableElementAt,
  fixedPointFor,
  isBindable,
  pointForFixedPoint,
} from "./binding.js";
export {
  distanceToElement,
  hit,
  isPointInside,
  isPointOnOutline,
  shouldTestInside,
} from "./hit-test.js";
export { ShapeGenerator } from "./shape-generator.js";
export {
  type RecognizedShape,
  type ShapeRecognition,
  ShapeRecognizer,
  isPolylineShape,
} from "./shape-recognizer.js";
export {
  type SnapResult,
  DEFAULT_SNAP_DISTANCE,
  NO_SNAP,
  gapSnap,
  snap,
  snapToGrid,
} from "./snapping.js";
