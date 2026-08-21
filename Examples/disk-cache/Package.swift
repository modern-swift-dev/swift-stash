// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiskCacheExample",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DiskCacheExample",
            dependencies: [
                .product(name: "SwiftStash", package: "swift-stash")
            ]
        )
    ]
)
