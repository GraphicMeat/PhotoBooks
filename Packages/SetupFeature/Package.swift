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
        .package(path: "../AppSupport"),
        .package(path: "../PhotoBookCore"),
        .package(path: "../PhotoBookImport")
    ],
    targets: [
        .target(
            name: "SetupFeature",
            dependencies: [
                "ModelLayer",
                "AppSupport",
                .product(name: "PhotoBookCore", package: "PhotoBookCore"),
                .product(name: "PhotoBookImport", package: "PhotoBookImport")
            ]
        ),
        .testTarget(
            name: "SetupFeatureTests",
            dependencies: [
                "SetupFeature",
                .product(name: "PhotoBookCore", package: "PhotoBookCore"),
                .product(name: "PhotoBookImport", package: "PhotoBookImport"),
                .product(name: "PhotoBookImportTestSupport", package: "PhotoBookImport")
            ]
        )
    ]
)
