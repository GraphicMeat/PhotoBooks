// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExportFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ExportFeature", targets: ["ExportFeature"])
    ],
    dependencies: [
        .package(path: "../ModelLayer"),
        .package(path: "../AppSupport")
    ],
    targets: [
        .target(
            name: "ExportFeature",
            dependencies: ["ModelLayer", "AppSupport"]
        )
    ]
)
