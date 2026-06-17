# Hand-Drawn Rendering

## Purpose

The sketchy, hand-drawn look of every shape in the drawing. This is a Swift port of rough.js (RoughKit) that reproduces its deterministic, seeded sketch geometry with numeric parity, plus a pressure-based freehand outline generator (FreehandKit) ported from perfect-freehand for natural pen and brush strokes.

## Requirements

### Requirement: Seeded deterministic randomness
The system SHALL provide a deterministic per-element pseudo-random generator using a 32-bit linear congruential scheme (seed advanced as `48271*seed` masked to 31 bits, then normalized into [0,1)), so that a given seed always yields the same sequence and rough.js-order advancement is reproduced (src: Sources/RoughKit/SeededRandom.swift:17).

#### Scenario: Same seed yields identical output
- GIVEN two generators created with the same seed
- WHEN the same sequence of draws is requested from each
- THEN both SHALL produce identical values in the same order (src: Tests/RoughKitTests/RoughGeneratorTests.swift:25)

#### Scenario: Values stay in range
- GIVEN a seeded generator
- WHEN successive values are drawn
- THEN each value SHALL fall in the half-open interval [0,1) (src: Tests/RoughKitTests/RoughGeneratorTests.swift:25)

### Requirement: Rough shape generation
The system SHALL generate hand-drawn geometry as polyline strokes with a double-stroke overlay (using `seed+1`) for roughness, building closed polygons and open paths from cubic Béziers and ellipses from per-stroke offset randomization combined with Catmull-Rom smoothing, and SHALL scale roughness down as line length grows (from 1.0 down to 0.4 across the 200–500px range) (src: Sources/RoughKit/RoughGenerator.swift:55, Sources/RoughKit/RoughGeneratorShapes.swift:25).

#### Scenario: Double stroke for roughness
- GIVEN a shape generated with roughness greater than zero
- WHEN its geometry is produced
- THEN it SHALL include an overlaid second stroke derived from `seed+1` (src: Sources/RoughKit/RoughGenerator.swift:55)

#### Scenario: Roughness reduced for long lines
- GIVEN a stroke whose length is large
- WHEN its roughness is computed
- THEN the effective roughness SHALL be reduced toward 0.4 as length grows past the 200–500px range (src: Sources/RoughKit/RoughGeneratorShapes.swift:25)

### Requirement: rough.js numeric parity
The system SHALL reproduce rough.js geometry to within a numeric tolerance of 1e-4, matching the upstream reference output for the same seed and options (src: Tests/RoughKitTests/RoughJSParityTests.swift:56).

#### Scenario: Rectangle matches rough.js reference
- GIVEN a rectangle generated at seed=1 with the same options as the rough.js reference
- WHEN its points are compared to the reference output
- THEN every coordinate SHALL match within 1e-4 (src: Tests/RoughKitTests/RoughJSParityTests.swift:56)

#### Scenario: Generation is deterministic within tolerance
- GIVEN the same shape generated twice with identical seed and options
- WHEN the two outputs are compared
- THEN they SHALL be identical within 1e-4 (src: Tests/RoughKitTests/RoughJSParityTests.swift:56)

### Requirement: Fill styles
The system SHALL support fill styles solid, hachure, cross-hatch, and zigzag, where solid emits a single closed `fillPath`, hachure emits rotated parallel scanlines computed by intersecting the fill polygon edges (emitted as `fillSketch`), cross-hatch emits two perpendicular hachure sets (producing more lines than plain hachure), and zigzag emits a continuous connected scanline path; the hachure gap SHALL default to `strokeWidth*4` with a minimum of 0.1 (src: Sources/RoughKit/RoughFiller.swift:27).

#### Scenario: Hachure produces parallel scanlines
- GIVEN a filled polygon with hachure fill style
- WHEN it is filled
- THEN the fill SHALL be emitted as `fillSketch` parallel scanlines spaced by the hachure gap (src: Tests/RoughKitTests/RoughShapesTests.swift:54)

#### Scenario: Cross-hatch has more lines than hachure
- GIVEN the same polygon filled with hachure and with cross-hatch
- WHEN the resulting scanlines are counted
- THEN cross-hatch SHALL contain more lines than plain hachure (src: Tests/RoughKitTests/RoughShapesTests.swift:79)

### Requirement: Catmull-Rom curve generation
The system SHALL generate smooth curves passing through a set of points using Catmull-Rom interpolation with tension `1 − curveTightness`, applying per-point jitter modulated by roughness and emitting dual strokes when roughness is greater than zero (src: Sources/RoughKit/RoughGeneratorShapes.swift:65).

#### Scenario: Curve passes through input points with jitter
- GIVEN a sequence of points and a roughness greater than zero
- WHEN a smooth curve is generated
- THEN the curve SHALL interpolate the points with roughness-modulated jitter and include a second overlaid stroke (src: Tests/RoughKitTests/RoughShapesTests.swift:44)

### Requirement: Drawable to CGPath conversion
The system SHALL convert a Drawable's path operations (`move`, `lineTo`, `bcurveTo`) into a `CGPath`, inserting an implicit move when there is no current point, and SHALL combine all `.path` op-sets into a single `CGPath` (src: Sources/RoughKit/RoughPath.swift:6).

#### Scenario: Path ops become a CGPath
- GIVEN a Drawable containing `.path` op-sets with move/lineTo/bcurveTo operations
- WHEN it is converted
- THEN the operations SHALL be merged into one `CGPath`, with a move inserted where no current point exists (src: Sources/RoughKit/RoughPath.swift:6)

### Requirement: Pressure-based freehand outlines
The system SHALL generate pressure-based freehand stroke outlines (a perfect-freehand port) from `(x, y, pressure∈[0,1])` samples, applying streamline smoothing (lerp by `1 − streamline`, default 0.5), computing per-point radius from pressure via sine easing and thinning (0.6), simulating pressure from movement speed when `simulatePressure` is true, producing a closed ribbon outline offset on both sides, and emitting a 16-segment circle for a single-point tap (src: Sources/FreehandKit/FreehandKit.swift:4).

#### Scenario: Single point becomes a circle
- GIVEN a single input sample
- WHEN an outline is generated
- THEN the outline SHALL be a 16-segment circle (src: Tests/FreehandKitTests/FreehandOutlineTests.swift:18)

#### Scenario: Higher pressure widens the ribbon
- GIVEN two strokes that differ only in pressure
- WHEN their outlines are generated
- THEN the higher-pressure stroke SHALL produce a wider ribbon (src: Tests/FreehandKitTests/FreehandOutlineTests.swift:59)

#### Scenario: Constant pressure gives even width
- GIVEN a straight stroke drawn at constant pressure
- WHEN its outline is generated
- THEN the ribbon SHALL have even width along its length and a monotonically increasing running length (src: Tests/FreehandKitTests/FreehandOutlineTests.swift:59)
