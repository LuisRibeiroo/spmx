// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "spmx",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SPMXCore",
            targets: ["SPMXCore"]
        ),
        .executable(
            name: "spmx",
            targets: ["spmx"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "SPMXCore",
            dependencies: []
        ),
        .executableTarget(
            name: "spmx",
            dependencies: [
                "SPMXCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "SPMXCoreTests",
            dependencies: ["SPMXCore"]
        )
    ]
)
