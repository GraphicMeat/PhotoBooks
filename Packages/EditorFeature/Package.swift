// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EditorFeature", targets: ["EditorFeature"])
    ],
    dependencies: [
        .package(path: "../ModelLayer"),
        .package(path: "../EditCore"),
        .package(path: "../AppSupport"),
        .package(path: "../SetupFeature"),
        .package(path: "../ExportFeature")
    ],
    targets: [
        .target(
            name: "EditorFeature",
            dependencies: ["ModelLayer", "EditCore", "AppSupport", "SetupFeature", "ExportFeature"]
        ),
        .testTarget(
            name: "EditorFeatureTests",
            dependencies: ["EditorFeature"]
        )
    ]
)
