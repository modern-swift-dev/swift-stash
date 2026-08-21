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
make site-setup    # Install the locked website dependencies
make site-validate # Type-check and build the Astro site
make site-build    # Replace docs/ with the Astro and DocC output
make site-preview  # Serve the assembled docs/ directory locally
make test-all      # Test all supported Apple platforms and Linux
```

For a direct SwiftPM test run, use:

```sh
swift test
```

## Publishing the documentation site

The Astro source is in `Website/`. `docs/` contains generated files for GitHub Pages and is committed so maintainers can review every site update.

For each release:

1. Publish the GitHub release.
2. Run `make site-setup` and `make site-build` from the repository root.
3. Confirm that the release card shows the published version and review the generated Astro and DocC changes in `docs/`.
4. Run `make site-preview` for a final local check, then commit `docs/` with the source changes.

The build stops if GitHub does not return a valid latest published release. It also checks internal links before replacing `docs/`.

GitHub Pages needs one manual repository setting. In **Settings > Pages**, choose **Deploy from a branch**, select `main`, select `/docs`, and save. GitHub documents these steps in [Configuring a publishing source for your GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site). The build does not change this remote setting.

## License

SwiftStash is available under the MIT License. See [LICENSE](LICENSE).
