// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EditCore", targets: ["EditCore"])
    ],
    dependencies: [
        .package(path: "../PhotoBookCore")
    ],
    targets: [
        .target(
            name: "EditCore",
            dependencies: [.product(name: "PhotoBookCore", package: "PhotoBookCore")]
        ),
        .testTarget(
            name: "EditCoreTests",
            dependencies: ["EditCore"]
        )
    ]
)
