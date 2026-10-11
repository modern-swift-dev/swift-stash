// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MemoryCacheExample",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "MemoryCacheExample",
            dependencies: [
                .product(name: "SwiftStash", package: "swift-stash")
            ]
        )
    ]
)
