// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelLayer",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ModelLayer", targets: ["ModelLayer"])
    ],
    dependencies: [
        .package(path: "../EditCore"),
        .package(path: "../AppSupport"),
        .package(path: "../PhotoBookCore"),
        .package(path: "../PhotoBookImport"),
        .package(path: "../PhotoBookRender")
    ],
    targets: [
        .target(
            name: "ModelLayer",
            dependencies: [
                "EditCore",
                "AppSupport",
                .product(name: "PhotoBookCore", package: "PhotoBookCore"),
                .product(name: "PhotoBookImport", package: "PhotoBookImport"),
                .product(name: "PhotoBookRender", package: "PhotoBookRender")
            ]
        ),
        .testTarget(
            name: "ModelLayerTests",
            dependencies: ["ModelLayer", "EditCore", "AppSupport"]
        )
    ]
)
