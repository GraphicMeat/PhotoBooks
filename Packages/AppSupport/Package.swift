// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppSupport",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AppSupport", targets: ["AppSupport"])
    ],
    dependencies: [
        .package(path: "../PhotoBookCore")
    ],
    targets: [
        .target(
            name: "AppSupport",
            dependencies: [.product(name: "PhotoBookCore", package: "PhotoBookCore")]
        ),
        .testTarget(
            name: "AppSupportTests",
            dependencies: ["AppSupport"]
        )
    ]
)
