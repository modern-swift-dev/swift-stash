// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftStash",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SwiftStash", targets: ["SwiftStash"])
    ],
    dependencies: [
        .package(url: "https://github.com/MobileNativeFoundation/Kronos.git", .upToNextMajor(from: "4.3.1")),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "6.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0")
    ],
    targets: [
        .target(
            name: "SwiftStash",
            dependencies: [
                .product(
                    name: "Kronos",
                    package: "Kronos",
                    condition: .when(platforms: [.iOS, .macOS, .tvOS, .macCatalyst])
                ),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux, .android, .windows, .openbsd, .wasi])
                )
            ]
        ),
        .testTarget(name: "SwiftStashTests", dependencies: ["SwiftStash"])
    ],
    swiftLanguageModes: [.v6]
)
