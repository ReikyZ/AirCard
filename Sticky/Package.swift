// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sticky",
    products: [
        .library(name: "StickyCore", targets: ["StickyCore"]),
    ],
    targets: [
        .target(name: "StickyCore"),
        .testTarget(
            name: "StickyCoreTests",
            dependencies: ["StickyCore"]
        ),
    ]
)
