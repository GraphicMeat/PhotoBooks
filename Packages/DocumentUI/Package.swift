// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocumentUI",
    defaultLocalization: "en",
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
            dependencies: ["ModelLayer", "EditorFeature", "SetupFeature", "ExportFeature", "AppSupport"],
            resources: [.process("Resources"), .process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "DocumentUITests",
            dependencies: ["DocumentUI", "ModelLayer"]
        )
    ]
)
