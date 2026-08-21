# SwiftStash

SwiftStash is a small, concurrency-safe cache for Swift. It provides an actor-isolated API, configurable FIFO, LIFO, and LRU eviction, and interchangeable memory or disk storage engines.

[Read the guide](https://modern-swift-dev.github.io/swift-stash/) or open the [SwiftStash API reference](https://modern-swift-dev.github.io/swift-stash/api/documentation/swiftstash/).

## Requirements

- Swift 6.0+
- macOS 15+
- iOS and tvOS 17+
- watchOS 10+
- visionOS 1+
- Linux with Swift 6.0+

## Installation

Add SwiftStash to your package dependencies:

```swift
dependencies: [
    .package(
        url: "https://github.com/modern-swift-dev/swift-stash.git",
        from: "1.1.0"
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

## Quick start

```swift
import SwiftStash

let storage = MemoryStorageEngine<String, String>()
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

Each cache has one key type. Use a string-backed enum when the set of keys is known:

```swift
enum ProfileKey: String, CacheKey {
    case current
    case selected
}

let storage = MemoryStorageEngine<ProfileKey, Profile>()
let cache = await Cache(storagePolicy: storage)

await cache.add(profile, for: .current)
let currentProfile = await cache[.current]
```

`String` also conforms to `CacheKey`. A custom key can conform by providing a lossless `stringValue` representation and `init?(stringValue:)`.

## Storage engines

`MemoryStorageEngine` gives the cache no persistent backing. Values remain in the `Cache` actor until they are removed or the cache is released.

`DiskStorageEngine` stores each entry in the app's caches directory. SwiftStash includes serializers for `Codable` values and strings:

```swift
let storage = DiskStorageEngine(
    directory: "profiles",
    keyType: ProfileKey.self,
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

- [Memory cache](Examples/memory-cache) - basic reads, writes, identifiable values, and count-based eviction.
- [Disk cache](Examples/disk-cache) - persistent `Codable` values with the JSON serializer.
- [Custom serializer](Examples/custom-serializer) - storing a custom value with a binary representation.

The [examples guide](https://modern-swift-dev.github.io/swift-stash/examples/) explains each program before showing its complete source.

Run one from the repository root:

```sh
swift run --package-path Examples/memory-cache
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, common commands, and documentation publishing instructions.

## License

SwiftStash is available under the MIT License. See [LICENSE](LICENSE).
