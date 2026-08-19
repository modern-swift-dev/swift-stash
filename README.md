# SwiftStash

SwiftStash is a small, concurrency-safe cache for Swift. It provides an actor-isolated API, configurable FIFO, LIFO, and LRU eviction, and interchangeable memory or disk storage engines.

## Requirements

- Swift 6.0+
- macOS 15+
- iOS and tvOS 17+
- watchOS 10+
- visionOS 1+

## Installation

Add SwiftStash to your package dependencies:

```swift
dependencies: [
    .package(
        url: "https://github.com/modern-swift-dev/swift-stash.git",
        branch: "main"
    )
]
```

Then add `SwiftStash` to the dependencies of your target:

```swift
.target(
    name: "MyTarget",
    dependencies: ["SwiftStash"]
)
```

Use a tagged version requirement instead of `branch` once the version you want is available.

## Quick start

```swift
import SwiftStash

let storage = MemoryStorageEngine<String>()
let cache = await Cache(
    policy: .lru(threshold: 5 * 60),
    storagePolicy: storage
)

await cache.add("Ada", for: "current-user")

if let name = await cache["current-user"] {
    print(name)
}

await cache.evictUntil(maxNbItems: 100)
```

`Cache` is an actor, so calls from outside its isolation domain use `await`. Values stored in a cache must be `Sendable`.

## Storage engines

`MemoryStorageEngine` gives the cache no persistent backing. Values remain in the `Cache` actor until they are removed or the cache is released.

`DiskStorageEngine` stores each entry in the app's caches directory. SwiftStash includes serializers for `Codable` values and strings:

```swift
let storage = DiskStorageEngine(
    directory: "profiles",
    serializer: JsonDiskStorageSerializer<Profile>()
)
let cache = await Cache(storagePolicy: storage)
```

The named subdirectory must exist before values are persisted. Disk writes report failure by returning `false` from the storage engine; cache mutation APIs do not throw when persistence fails. See the complete disk example for directory setup.

You can support another persistence mechanism by conforming a type to `StorageEngine`, or support another disk representation by conforming to `DiskStorageSerializer`.

## Eviction

Choose a policy when creating a cache:

- `fifo(threshold:)` removes the oldest entries first.
- `lifo(threshold:)` removes the newest entries first when reducing by count.
- `lru(threshold:)` removes the least recently accessed entries first.

The threshold is measured in seconds. Call `evictExpired()` to remove expired entries, or `evictUntil(maxNbItems:)` to remove expired entries and enforce a maximum count. Eviction is explicit; SwiftStash does not start a background timer.

## Examples

The examples are independent, executable Swift packages:

- [Memory cache](docs/examples/memory-cache) — basic reads, writes, identifiable values, and count-based eviction.
- [Disk cache](docs/examples/disk-cache) — persistent `Codable` values with the JSON serializer.
- [Custom serializer](docs/examples/custom-serializer) — storing a custom value with a binary representation.

Run one from the repository root:

```sh
swift run --package-path docs/examples/memory-cache
```

## Development

Install the contributor tools and Git hooks with:

```sh
make setup
```

This installs the Homebrew and Mint dependencies declared by the project and configures [Lefthook](https://github.com/evilmartians/lefthook). Lefthook runs the repository's configured checks from Git hooks so formatting and lint issues are caught before changes are committed.

The `Makefile` provides the common development commands:

```sh
make test          # Run the Swift package tests
make lint          # Check the Swift sources with SwiftLint
make format        # Apply SwiftFormat and SwiftLint fixes
make documentation # Build the API documentation
make test-all      # Test all supported Apple platforms and Linux
```

For a direct SwiftPM test run, use:

```sh
swift test
```

## License

SwiftStash is available under the MIT License. See [LICENSE](LICENSE).
