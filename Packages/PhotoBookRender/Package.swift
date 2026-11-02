// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoBookRender",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PhotoBookRender", targets: ["PhotoBookRender"])
    ],
    dependencies: [
        .package(path: "../PhotoBookCore")
    ],
    targets: [
        .target(
            name: "PhotoBookRender",
            dependencies: [
                .product(name: "PhotoBookCore", package: "PhotoBookCore")
            ],
            resources: [.process("Resources"), .process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "PhotoBookRenderTests",
            dependencies: [
                "PhotoBookRender",
                .product(name: "PhotoBookCore", package: "PhotoBookCore")
            ],
            exclude: ["Goldens"]
        )
    ]
)
