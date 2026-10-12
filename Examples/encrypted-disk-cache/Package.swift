// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EncryptedDiskCacheExample",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
        // SymmetricKey comes from CryptoKit on Apple platforms and from swift-crypto elsewhere.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "EncryptedDiskCacheExample",
            dependencies: [
                .product(name: "SwiftStash", package: "swift-stash"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux, .android, .windows, .openbsd, .wasi])
                )
            ]
        )
    ]
)
