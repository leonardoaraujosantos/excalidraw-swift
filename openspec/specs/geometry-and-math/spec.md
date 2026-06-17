# Geometry & Math

## Purpose

The framework-light geometric and numeric foundation used by rendering and editing: 2D points and vectors, angles and numeric utilities, bounding boxes, outline extraction, hit-testing, intersections (lines, segments, ellipses, rectangles, triangles, Bézier curves), procedural shape generation, viewport culling, dirty-region tracking, frame containment, snapping/guides, and heading quantization. These primitives carry no UI dependencies so they can be reused and tested in isolation.

## Requirements

### Requirement: 2D point primitives
The system SHALL represent a 2D point as `x`/`y` and SHALL support add, subtract, Euclidean distance, squared distance, rotate-around-center, translate, midpoint, scale-from-origin, in-bounds test, and approximate equality, and SHALL JSON-code each point as a two-element `[x, y]` array to match the `.excalidraw` wire format. (src: Sources/ExcalidrawMath/Point.swift:9)

#### Scenario: Point JSON round-trips as an array
- GIVEN a point `(x, y)`
- WHEN it is encoded to JSON and decoded back
- THEN it SHALL serialize as `[x, y]` and decode to the same point (src: Sources/ExcalidrawMath/Point.swift:37)

#### Scenario: Distance between two points
- GIVEN two points
- WHEN their distance is requested
- THEN the system SHALL return the Euclidean distance between them (src: Sources/ExcalidrawMath/Point.swift:19)

### Requirement: 2D vector primitives
The system SHALL represent a 2D vector as `u`/`v` and SHALL support add, subtract, scalar multiply, scalar cross product (z component), dot product, magnitude, normalization, the right normal, and conversion to a point with an offset. (src: Sources/ExcalidrawMath/Vector.swift:1)

#### Scenario: Normalized vector has unit magnitude
- GIVEN a non-zero vector
- WHEN it is normalized
- THEN the result SHALL have magnitude 1 and the same direction (src: Sources/ExcalidrawMath/Vector.swift:1)

### Requirement: Angle utilities
The system SHALL normalize an angle into `[0, 2π)`, convert between degrees and radians, convert cartesian coordinates to polar, detect right angles, test whether an angle lies in a range with wraparound, and compute the smallest signed difference between two angles. (src: Sources/ExcalidrawMath/Angle.swift:6)

#### Scenario: Angle normalized into the canonical range
- GIVEN an angle outside `[0, 2π)`
- WHEN it is normalized
- THEN the result SHALL lie in `[0, 2π)` and represent the same direction (src: Sources/ExcalidrawMath/Angle.swift:6)

### Requirement: Numeric utilities and ranges
The system SHALL provide clamp, round-to-precision (floor/ceil/round variants), round-to-step, average, and approximate equality, and SHALL provide ranges supporting overlap, intersection, and contains tests. (src: Sources/ExcalidrawMath/Utils.swift:4)

#### Scenario: Clamp bounds a value
- GIVEN a value and a `[min, max]` range
- WHEN the value is clamped
- THEN the result SHALL be `min` if below, `max` if above, else the value unchanged (src: Sources/ExcalidrawMath/Utils.swift:4)

#### Scenario: Range overlap and intersection
- GIVEN two numeric ranges
- WHEN their overlap is queried
- THEN the system SHALL report whether they overlap and return their intersection when they do (src: Sources/ExcalidrawMath/Range.swift:13)

### Requirement: Bounding boxes
The system SHALL compute an axis-aligned bounding box (`minX`/`minY`/`maxX`/`maxY`) for an element accounting for its rotation, SHALL compute the smallest box enclosing a set of points, SHALL test whether a point lies inside a box, and SHALL union two boxes. (src: Sources/ExcalidrawGeometry/BoundingBox.swift:1)

#### Scenario: Rotated element bounds enclose the rotated shape
- GIVEN an element with a non-zero rotation angle
- WHEN its bounds are computed
- THEN the box SHALL enclose the element's rotated outline (src: Sources/ExcalidrawGeometry/ElementGeometry.swift:38)

#### Scenario: Union of two boxes
- GIVEN two bounding boxes
- WHEN they are unioned
- THEN the result SHALL be the smallest box containing both (src: Sources/ExcalidrawGeometry/BoundingBox.swift:1)

### Requirement: Element outline extraction
The system SHALL extract an element's outline as unrotated scene-space vertices with a closed-path flag, producing four vertices for a diamond, four for a rectangle, an approximate four-vertex box for an ellipse, the element's points for lines/arrows and freedraw, and a four-corner fallback for other types. (src: Sources/ExcalidrawGeometry/ElementGeometry.swift:73)

#### Scenario: Diamond outline has four vertices
- GIVEN a diamond element
- WHEN its outline is extracted
- THEN the outline SHALL have four vertices and be marked closed (src: Sources/ExcalidrawGeometry/ElementGeometry.swift:87)

#### Scenario: Arrow outline is an open polyline
- GIVEN an arrow element
- WHEN its outline is extracted
- THEN the outline SHALL be the arrow's scene points marked not closed (src: Sources/ExcalidrawGeometry/ElementGeometry.swift:92)

### Requirement: Point-in-polygon
The system SHALL test point-in-polygon membership using an even-odd ray cast and SHALL also provide a non-zero winding test for self-intersecting polygons. (src: Sources/ExcalidrawMath/Polygon.swift:17)

#### Scenario: Self-intersecting polygon uses winding rule
- GIVEN a self-intersecting polygon and a point in its overlapping interior
- WHEN membership is tested with the non-zero winding rule
- THEN the point SHALL be reported inside (src: Sources/ExcalidrawMath/Polygon.swift:17)

### Requirement: Hit testing with threshold
The system SHALL hit-test a point against an element within a threshold, selecting from-inside testing versus outline-only testing depending on whether the element is filled, text, or image; SHALL provide a strict interior test, an outline-proximity test, and the shortest distance to the outline; and SHALL early-out using the rotated bounds. (src: Sources/ExcalidrawGeometry/HitTest.swift:14)

#### Scenario: Filled shape is hit from its interior
- GIVEN a filled element and a point inside it
- WHEN the point is hit-tested
- THEN the system SHALL report a hit (src: Tests/ExcalidrawGeometryTests/HitTestTests.swift:1)

#### Scenario: Unfilled shape is hit only near its outline
- GIVEN an unfilled element and a point in its interior but far from the outline
- WHEN the point is hit-tested within the threshold
- THEN the system SHALL report no hit (src: Tests/ExcalidrawGeometryTests/HitTestTests.swift:1)

### Requirement: Ellipse geometry
The system SHALL test point inclusion in an ellipse, compute distance to an ellipse via Newton iteration, and compute segment-ellipse and line-ellipse intersections. (src: Sources/ExcalidrawMath/Ellipse.swift:16)

#### Scenario: Point inside an ellipse
- GIVEN an ellipse and an interior point
- WHEN inclusion is tested
- THEN the system SHALL report the point inside (src: Sources/ExcalidrawMath/Ellipse.swift:16)

#### Scenario: Segment crossing an ellipse
- GIVEN a segment that crosses an ellipse boundary
- WHEN intersections are computed
- THEN the system SHALL return the crossing point(s) on the boundary (src: Sources/ExcalidrawMath/Ellipse.swift:16)

### Requirement: Line and segment geometry
The system SHALL compute point-to-segment distance with endpoint clamping, an on-segment test, segment-segment intersection using half-open `[0, 1)` parameters, segment-as-infinite-line intersection, and segment-to-segment distance. (src: Sources/ExcalidrawMath/LineSegment.swift:20)

#### Scenario: Point-to-segment distance clamps to endpoints
- GIVEN a point whose nearest projection falls beyond a segment endpoint
- WHEN the distance is computed
- THEN the result SHALL be the distance to that endpoint (src: Sources/ExcalidrawMath/LineSegment.swift:20)

#### Scenario: Crossing segments intersect
- GIVEN two segments that cross
- WHEN their intersection is computed with half-open `[0, 1)` parameters
- THEN the system SHALL return the crossing point (src: Sources/ExcalidrawMath/LineSegment.swift:20)

### Requirement: Rectangle and triangle geometry
The system SHALL compute intersections of a rectangle's edges with a segment, test whether two rectangles overlap, and test point-in-triangle membership using barycentric coordinates. (src: Sources/ExcalidrawMath/Rectangle.swift:19)

#### Scenario: Segment crossing a rectangle edge
- GIVEN a segment crossing a rectangle edge
- WHEN rectangle-segment intersections are computed
- THEN the system SHALL return the crossing point on that edge (src: Sources/ExcalidrawMath/Rectangle.swift:19)

#### Scenario: Point inside a triangle
- GIVEN a triangle and an interior point
- WHEN membership is tested via barycentric coordinates
- THEN the system SHALL report the point inside (src: Sources/ExcalidrawMath/Triangle.swift:14)

### Requirement: Cubic Bézier curves
The system SHALL evaluate a cubic Bézier at parameter `t`, compute its tangent, compute arc length via 24-point Legendre-Gauss quadrature, parameterize by length via binary search, compute curve-line intersections via Newton iteration with an analytic Jacobian, and find the closest point on the curve via a coarse scan followed by golden-section refinement. (src: Sources/ExcalidrawMath/Curve.swift:8)

#### Scenario: Arc length of a curve
- GIVEN a cubic Bézier curve
- WHEN its arc length is computed
- THEN the system SHALL return the length via 24-point Legendre-Gauss quadrature (src: Tests/ExcalidrawMathTests/CurveMathTests.swift:46)

#### Scenario: Closest point on a curve
- GIVEN a cubic Bézier curve and an arbitrary query point
- WHEN the closest point is requested
- THEN the system SHALL return the on-curve point minimizing distance via coarse scan and golden-section refinement (src: Tests/ExcalidrawMathTests/CurveMathTests.swift:46)

### Requirement: Procedural shape generation
The system SHALL generate the geometry of regular polygons, stars (parameterized by point count and inner ratio), hearts (parametric), clouds (lobed), and speech bubbles (rounded body plus tail). (src: Sources/ExcalidrawGeometry/ShapeGenerator.swift:9)

#### Scenario: Star with a given point count
- GIVEN a requested point count and inner ratio
- WHEN a star is generated
- THEN the system SHALL produce a star outline with that many points and the given inner radius ratio (src: Sources/ExcalidrawGeometry/ShapeGenerator.swift:9)

### Requirement: Viewport culling
The system SHALL keep only the elements whose bounds intersect the viewport expanded by a stroke-width margin. (src: Sources/ExcalidrawGeometry/Culling.swift:7)

#### Scenario: Off-screen element is culled
- GIVEN an element whose bounds lie outside the expanded viewport
- WHEN culling runs
- THEN that element SHALL be excluded from the result (src: Tests/ExcalidrawGeometryTests/CullingTests.swift:1)

### Requirement: Dirty-region tracking
The system SHALL compute the minimal redraw region as the union of the bounds of added, removed, and modified elements. (src: Sources/ExcalidrawGeometry/DirtyRegion.swift:7)

#### Scenario: Dirty region unions changed bounds
- GIVEN a set of added, removed, and modified elements
- WHEN the dirty region is computed
- THEN the result SHALL be the union of all their bounds (src: Sources/ExcalidrawGeometry/DirtyRegion.swift:7)

### Requirement: Frame containment
The system SHALL provide an is-frame test, find the topmost frame containing an element's center, and enumerate the children of a frame. (src: Sources/ExcalidrawGeometry/Frames.swift:9)

#### Scenario: Topmost frame containing an element
- GIVEN overlapping frames and an element
- WHEN the containing frame is queried
- THEN the system SHALL return the topmost frame whose area contains the element's center (src: Sources/ExcalidrawGeometry/Frames.swift:9)

### Requirement: Snapping and guides
The system SHALL snap a point to the grid, SHALL snap a moving box to static elements' edges and centers within a threshold returning the snap offset plus guide lines, and SHALL support gap snapping and distribution including centering within gaps and repeating existing gaps. (src: Sources/ExcalidrawGeometry/Snapping.swift:21)

#### Scenario: Moving box snaps to a static edge
- GIVEN a moving box near a static element's edge within the threshold
- WHEN snapping is computed
- THEN the system SHALL return an offset aligning the edges plus the corresponding guide line (src: Tests/ExcalidrawGeometryTests/SnappingTests.swift:1)

#### Scenario: Point snaps to the grid
- GIVEN a point and a grid size
- WHEN it is snapped to the grid
- THEN the result SHALL be the nearest grid intersection (src: Sources/ExcalidrawGeometry/Snapping.swift:21)

### Requirement: Heading and direction quantization
The system SHALL provide cardinal up/right/down/left heading utilities to quantize a vector to a cardinal direction, derive headings from boxes, and flip and measure headings. (src: Sources/ExcalidrawGeometry/Heading.swift:1)

#### Scenario: Vector quantized to a cardinal heading
- GIVEN an arbitrary direction vector
- WHEN it is quantized
- THEN the system SHALL return the nearest cardinal heading (up, right, down, or left) (src: Sources/ExcalidrawGeometry/Heading.swift:1)
