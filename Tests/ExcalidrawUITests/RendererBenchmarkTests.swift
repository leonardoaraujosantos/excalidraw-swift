import ExcalidrawMetal
import ExcalidrawModel
import XCTest
@testable import ExcalidrawUI

final class RendererBenchmarkTests: XCTestCase {
    func testSyntheticSceneSizesAndKinds() {
        let shapes = RendererBenchmark.syntheticScene(count: 40, kind: .shapes)
        XCTAssertEqual(shapes.visibleElements.count, 40)
        XCTAssertFalse(shapes.visibleElements.contains { $0.type == "freedraw" })

        let mixed = RendererBenchmark.syntheticScene(count: 40, kind: .mixed)
        XCTAssertTrue(mixed.visibleElements.contains { $0.type == "freedraw" })
    }

    func testAllTypesSceneCoversEveryComponentKind() {
        let scene = RendererBenchmark.syntheticScene(count: 64, kind: .all)
        let types = Set(scene.visibleElements.map(\.type))
        // Every component type must appear.
        for type in ["rectangle", "ellipse", "diamond", "arrow", "freedraw", "image", "text"] {
            XCTAssertTrue(types.contains(type), "missing \(type)")
        }
        // It includes a dashed rectangle and an image file.
        XCTAssertTrue(scene.visibleElements.contains { $0.base.strokeStyle == .dashed })
        XCTAssertFalse(scene.files.isEmpty)
    }

    func testRunProducesRowsWithPositiveCPUTimes() {
        let configs = [RendererBenchmark.Config(label: "all", kind: .all, count: 64)]
        let rows = RendererBenchmark.run(width: 400, height: 300, iterations: 1, configs: configs)
        XCTAssertEqual(rows.count, 1)
        let row = try? XCTUnwrap(rows.first)
        XCTAssertEqual(row?.count, 64)
        XCTAssertGreaterThan(row?.cpuMs ?? 0, 0)
    }

    func testRunPopulatesMetalAndHybridWhenAvailable() throws {
        try XCTSkipUnless(RendererBenchmark.metalAvailable, "No Metal device on this host")
        let configs = [RendererBenchmark.Config(label: "all", kind: .all, count: 64)]
        let row = try XCTUnwrap(
            RendererBenchmark.run(width: 400, height: 300, iterations: 1, configs: configs).first
        )
        XCTAssertNotNil(row.metalMs)
        XCTAssertNotNil(row.metalDirectMs)
        XCTAssertNotNil(row.hybridMs)
        XCTAssertNotNil(row.gpuMs)
        XCTAssertNotNil(row.ratio)
        XCTAssertNotNil(row.directRatio)
        XCTAssertNotNil(row.hybridRatio)
    }

    func testMetalAvailabilityMatchesContext() {
        XCTAssertEqual(RendererBenchmark.metalAvailable, MetalSceneRenderer.isSupported)
    }
}
