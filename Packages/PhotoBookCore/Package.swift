// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoBookCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PhotoBookCore", targets: ["PhotoBookCore"]),
        .executable(name: "photobook-demo", targets: ["photobook-demo"])
    ],
    targets: [
        .target(
            name: "PhotoBookCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "photobook-demo",
            dependencies: ["PhotoBookCore"]
        ),
        .testTarget(
            name: "PhotoBookCoreTests",
            dependencies: ["PhotoBookCore"]
        )
    ]
)
