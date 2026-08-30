// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fakthis",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Fakthis", targets: ["Fakthis"]),
        .executable(name: "FakthisApp", targets: ["FakthisApp"]),
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
            path: "App",
            exclude: ["Info.plist"],
            // `swift run` is not an .app bundle, so TCC will not find a usage string unless
            // it is embedded in the binary. Without this, beginTake fails silently and a
            // Speak press never lands a take.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "App/Info.plist",
                ])
            ]
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
