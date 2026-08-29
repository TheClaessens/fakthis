// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fakthis",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Fakthis", targets: ["Fakthis"]),
        .executable(name: "FakthisApp", targets: ["FakthisApp"]),
        .executable(name: "FakthisPrototype", targets: ["FakthisPrototype"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
    ],
    targets: [
        .target(
            name: "Fakthis",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "whisper",
            ]
        ),
        // The window. macOS app on the Fakthis library; Session is the only state it has.
        .executableTarget(
            name: "FakthisApp",
            dependencies: ["Fakthis"],
            path: "App"
        ),
        // THROWAWAY. UI-shell prototype, branch prototype/ui-shell. Not shipped.
        .executableTarget(
            name: "FakthisPrototype",
            dependencies: ["Fakthis"],
            path: "Prototype",
            exclude: ["Shots"]
        ),
        .testTarget(
            name: "FakthisTests",
            dependencies: ["Fakthis"]
        ),
        .binaryTarget(
            name: "whisper",
            path: "Vendor/whisper.xcframework"
        ),
    ]
)
