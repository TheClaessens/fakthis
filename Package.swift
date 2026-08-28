// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fakthis",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Fakthis", targets: ["Fakthis"]),
    ],
    targets: [
        .target(name: "Fakthis"),
        .testTarget(
            name: "FakthisTests",
            dependencies: ["Fakthis"]
        ),
    ]
)
