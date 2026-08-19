// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CustomSerializerExample",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../..")
    ],
    targets: [
        .executableTarget(
            name: "CustomSerializerExample",
            dependencies: [
                .product(name: "SwiftStash", package: "swift-stash")
            ]
        )
    ]
)
