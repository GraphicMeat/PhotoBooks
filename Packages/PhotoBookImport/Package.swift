// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoBookImport",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PhotoBookImport", targets: ["PhotoBookImport"]),
        .library(name: "PhotoBookImportTestSupport", targets: ["PhotoBookImportTestSupport"])
    ],
    dependencies: [
        .package(path: "../PhotoBookCore")
    ],
    targets: [
        .target(
            name: "PhotoBookImport",
            dependencies: [
                .product(name: "PhotoBookCore", package: "PhotoBookCore")
            ]
        ),
        .target(
            name: "PhotoBookImportTestSupport",
            dependencies: [
                "PhotoBookImport",
                .product(name: "PhotoBookCore", package: "PhotoBookCore")
            ]
        ),
        .testTarget(
            name: "PhotoBookImportTests",
            dependencies: [
                "PhotoBookImport",
                "PhotoBookImportTestSupport",
                .product(name: "PhotoBookCore", package: "PhotoBookCore")
            ]
        )
    ]
)
