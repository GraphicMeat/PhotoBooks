// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SetupFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SetupFeature", targets: ["SetupFeature"])
    ],
    dependencies: [
        .package(path: "../ModelLayer"),
        .package(path: "../AppSupport")
    ],
    targets: [
        .target(
            name: "SetupFeature",
            dependencies: ["ModelLayer", "AppSupport"]
        )
    ]
)
