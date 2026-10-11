# SwiftStash

SwiftStash is a small, concurrency-safe cache for Swift. It provides an actor-isolated API, configurable FIFO, LIFO, and LRU eviction, and interchangeable memory or disk storage engines.

[Read the guide](https://modern-swift-dev.github.io/docs/swift-stash/) or open the [SwiftStash API reference](https://modern-swift-dev.github.io/docs/swift-stash/api/documentation/swiftstash/).

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

`DiskStorageEngine` stores each entry in the app's caches directory, in a folder named after the bundle identifier. Processes without a bundle identifier, such as command-line tools, use their process name instead. SwiftStash includes serializers for `Codable` values and strings:

```swift
let storage = DiskStorageEngine(
    directory: "profiles",
    keyType: ProfileKey.self,
    serializer: JsonDiskStorageSerializer<Profile>()
)
let cache = await Cache(storagePolicy: storage)
```

The engine creates the named subdirectory when it is initialized. Disk writes report failure by returning `false` from the storage engine; cache mutation APIs do not throw when persistence fails.

Disk timestamps preserve fractional seconds. Existing ISO-8601 entries remain readable, but older SwiftStash releases cannot read the new numeric timestamp format.

You can support another persistence mechanism by conforming a type to `StorageEngine`, or support another disk representation by conforming to `DiskStorageSerializer`.

## Eviction

Choose a policy when creating a cache:

- `fifo(threshold:)` removes the oldest entries first.
- `lifo(threshold:)` removes the newest entries first when reducing by count.
- `lru(threshold:)` removes the least recently accessed entries first.

The threshold is measured in seconds. Call `evictExpired()` to remove expired entries, or `evictUntil(maxNbItems:)` to remove expired entries and enforce a maximum count. Eviction is explicit; SwiftStash does not start a background timer.

## Time

A cache reads the time from its clock, which defaults to `NetworkTimeClock.shared`. That clock uses the system date until you synchronize it with network time. On iOS, macOS, tvOS, and Mac Catalyst, synchronize it once early in your app's lifetime so expiration doesn't depend on the device's date setting:

```swift
NetworkTimeClock.shared.synchronize()
```

Synchronization uses [Kronos](https://github.com/MobileNativeFoundation/Kronos) to query NTP servers and finishes in the background; the clock keeps using the system date until it succeeds. On watchOS, visionOS, and Linux, the clock always uses the system date.

### Testing

Pass a `ManualClock` to test expiration and eviction without waiting for real time to pass:

```swift
let clock = ManualClock()
let cache = await Cache(
    policy: .fifo(threshold: 60),
    storagePolicy: MemoryStorageEngine<String, String>(),
    clock: clock
)

await cache.add("Ada", for: "current-user")
clock.advance(by: 60)
await cache.evictExpired()
```

Each `ManualClock` is independent, so tests that use separate clocks can run in parallel.

## Examples

The examples are independent, executable Swift packages:

- [Memory cache](Examples/memory-cache) - basic reads, writes, identifiable values, and count-based eviction.
- [Disk cache](Examples/disk-cache) - persistent `Codable` values with the JSON serializer.
- [Custom serializer](Examples/custom-serializer) - storing a custom value with a binary representation.

The [examples guide](https://modern-swift-dev.github.io/docs/swift-stash/examples/) explains each program before showing its complete source.

Run one from the repository root:

```sh
swift run --package-path Examples/memory-cache
```

## Contributing

Guides and examples live in [Documentation/Site](Documentation/Site). The [central documentation repository](https://github.com/modern-swift-dev/docs) owns the shared Astro theme, builds the guides and DocC API reference, and publishes them daily. For local builds and previews, follow the [docs README](https://github.com/modern-swift-dev/docs/blob/main/README.md).

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, common commands, and documentation publishing instructions.

## License

SwiftStash is available under the MIT License. See [LICENSE](LICENSE).
