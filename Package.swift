// swift-tools-version: 6.0
import PackageDescription

// Layered package graph for the Excalidraw → SwiftUI port.
// Pure-logic libraries build on both iOS and macOS so they are testable via
// `swift test` on the CI host without a simulator. UI/render layers are kept
// cross-platform for now (CoreGraphics/SwiftUI), with UIKit-only code guarded
// behind `#if canImport(UIKit)` as it lands.
let package = Package(
    name: "ExcalidrawSwift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ExcalidrawMath", targets: ["ExcalidrawMath"]),
        .library(name: "ExcalidrawModel", targets: ["ExcalidrawModel"]),
        .library(name: "ExcalidrawGeometry", targets: ["ExcalidrawGeometry"]),
        .library(name: "RoughKit", targets: ["RoughKit"]),
        .library(name: "FreehandKit", targets: ["FreehandKit"]),
        .library(name: "ExcalidrawRender", targets: ["ExcalidrawRender"]),
        .library(name: "ExcalidrawUI", targets: ["ExcalidrawUI"]),
    ],
    targets: [
        // MARK: Domain core
        .target(name: "ExcalidrawMath"),
        .target(name: "ExcalidrawModel", dependencies: ["ExcalidrawMath"]),
        .target(
            name: "ExcalidrawGeometry",
            dependencies: ["ExcalidrawMath", "ExcalidrawModel"]
        ),

        // MARK: Render building blocks
        .target(name: "RoughKit", dependencies: ["ExcalidrawMath"]),
        .target(name: "FreehandKit", dependencies: ["ExcalidrawMath"]),
        .target(
            name: "ExcalidrawRender",
            dependencies: ["ExcalidrawModel", "ExcalidrawGeometry", "RoughKit", "FreehandKit"]
        ),

        // MARK: UI layer
        .target(name: "ExcalidrawUI", dependencies: ["ExcalidrawRender"]),

        // MARK: Tests (one per library)
        .testTarget(name: "ExcalidrawMathTests", dependencies: ["ExcalidrawMath"]),
        .testTarget(name: "ExcalidrawModelTests", dependencies: ["ExcalidrawModel"]),
        .testTarget(name: "ExcalidrawGeometryTests", dependencies: ["ExcalidrawGeometry"]),
        .testTarget(name: "RoughKitTests", dependencies: ["RoughKit"]),
        .testTarget(name: "FreehandKitTests", dependencies: ["FreehandKit"]),
        .testTarget(name: "ExcalidrawRenderTests", dependencies: ["ExcalidrawRender"]),
        .testTarget(name: "ExcalidrawUITests", dependencies: ["ExcalidrawUI"]),
    ],
    swiftLanguageModes: [.v5]
)
