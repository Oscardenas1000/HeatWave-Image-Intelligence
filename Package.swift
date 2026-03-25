// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HeatWaveImageIntelligence",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HeatWaveImageClientCore",
            targets: ["HeatWaveImageClientCore"]
        ),
        .executable(
            name: "HeatWaveImageIntelligenceMac",
            targets: ["HeatWaveImageIntelligenceMac"]
        ),
    ],
    targets: [
        .target(
            name: "HeatWaveImageClientCore"
        ),
        .executableTarget(
            name: "HeatWaveImageIntelligenceMac",
            dependencies: ["HeatWaveImageClientCore"],
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "HeatWaveImageClientCoreTests",
            dependencies: ["HeatWaveImageClientCore"]
        ),
    ]
)
