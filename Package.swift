// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioSettings",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AudioSettings", targets: ["AudioSettings"])
    ],
    targets: [
        .executableTarget(
            name: "AudioSettings"
        )
    ]
)
