// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocumentUI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DocumentUI", targets: ["DocumentUI"])
    ],
    dependencies: [
        .package(path: "../ModelLayer"),
        .package(path: "../EditorFeature"),
        .package(path: "../SetupFeature"),
        .package(path: "../ExportFeature"),
        .package(path: "../AppSupport")
    ],
    targets: [
        .target(
            name: "DocumentUI",
            dependencies: ["ModelLayer", "EditorFeature", "SetupFeature", "ExportFeature", "AppSupport"]
        ),
        .testTarget(
            name: "DocumentUITests",
            dependencies: ["DocumentUI", "ModelLayer"]
        )
    ]
)
