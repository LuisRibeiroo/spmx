// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pspm",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PSPMCore",
            targets: ["PSPMCore"]
        ),
        .executable(
            name: "pspm",
            targets: ["pspm"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "PSPMCore",
            dependencies: []
        ),
        .executableTarget(
            name: "pspm",
            dependencies: [
                "PSPMCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "PSPMCoreTests",
            dependencies: ["PSPMCore"]
        )
    ]
)
