# Changelog

All notable changes to SwiftStash are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `CacheClock`, a protocol for the cache's source of time, and a `clock` parameter on `Cache.init`.
- `ManualClock`, an independent clock for testing expiration and eviction.
- `Cache.contains(_:)`, which checks for an unexpired entry without recording an access.
- A `maxCount` parameter on `Cache.init` that evicts down to a maximum entry count after each addition.
- `TextDiskStorageSerializer`, a non-generic replacement for `StringDiskStorageSerializer`.
- An `accessCount` parameter on `CacheEntry.init(key:value:creation:lastAccess:)`.
- CI coverage for Swift 6.0, tvOS, watchOS, visionOS, and the example packages.
- Per-entry lifetimes: an `expiresAfter` parameter on the `add` methods, and `CacheEntry.expiration`. An entry expires at its own expiration date or at the policy's threshold, whichever comes first. Disk storage persists the expiration.
- Cost limits: a `costLimit` parameter on `Cache.init` takes a maximum total cost and a function that computes each value's cost. The cache evicts entries in policy order after each addition to stay within the limit. `Cache.totalCost` and `CacheEntry.cost` report the costs.
- Entry file encryption: every `DiskStorageEngine` initializer accepts an optional `encryptionKey`. With one, each entry file is encrypted with AES-256-GCM, including its cache key and entry metadata, and named with a keyed hash of its cache key. SwiftStash doesn't create or store encryption keys; the app supplies its own. An encryption key shorter than 256 bits stops the process.
- Lazy loading: a cache backed by `DiskStorageEngine` reads only entry metadata when it's created and reads each value on first use. `Cache.unloadValues()` releases loaded values from memory. Custom storage engines can opt in by implementing the new `StorageEngine` requirements `loadMetadata()`, `loadValue(for:)`, and `delete(forKey:)`, which have default implementations, and returning `CacheEntryMetadata`.

### Changed

- **Breaking:** `Cache` has a single generic parameter, its storage engine. Replace `Cache<Engine, Value>` with `Cache<Engine>`; the value type is available as `Cache.CacheType`.
- Reads (the subscript, `entry(for:)`, and `values()`) no longer return expired entries; reading one removes it.
- Caches with the FIFO or LIFO policy no longer persist an access on every read. LRU caches still do.
- `Cache.init` is synchronous. Existing `await Cache(...)` calls still compile, with a warning.
- `DiskStorageEngine` creates its named directory during initialization.
- `DiskStorageEngine.clear()` removes only `.cache_entry` files, leaving other files in the directory.
- `DiskStorageEngine` stores each entry's access count. Older releases ignore it; entries they wrote load with a count of zero.
- Processes without a bundle identifier, such as command-line tools, store disk entries under their process name instead of a shared `app-cache-cache` directory. Entries they stored before are no longer found.
- Disk entry filenames are SHA-256 hashes on every platform. Linux uses swift-crypto, a new dependency on non-Apple platforms. Existing entries are renamed when loaded.
- Eviction breaks ties between equal dates by key, so the order no longer varies between runs.
- The minimum macOS version is 14.
- swift-docc-plugin is required from 1.5.0 instead of exactly 1.5.0.
- `EvictionPolicy` is a top-level `Sendable`, `Equatable` enum. `Cache.EvictionPolicy` remains as an alias.
- `values()` no longer records an access to each entry, so it doesn't change LRU order or lifetimes.
- Disk entry files hold a small metadata header followed by the raw serialized value, instead of pretty-printed JSON with a base64-encoded value, so they take about a quarter less space. Files from earlier releases are rewritten in the new format when loaded; earlier releases can't read the new format.
- With the LRU policy, a read updates only the metadata header of its disk entry file instead of rewriting the value. Storage engines can support this by implementing the new `StorageEngine.persistMetadata(_:)` requirement, which has a default implementation.
- Each cache runs on its own serial dispatch queue, so storage engine I/O no longer blocks a thread of Swift's cooperative pool. Creating a cache no longer loads its entries; it loads them on that queue when first used.

### Removed

These are breaking changes. Each removed API has a replacement:

- `MonotonicClock` is renamed `NetworkTimeClock`. Its test controls (`set(unixTimestamp:)`, `reset(...)`, and `tick(...)`) are removed; pass a `ManualClock` to the cache instead.
- `Date.monotonic` and `Date.timeIntervalSinceMonotonic` are removed; use `NetworkTimeClock.shared.now`.
- `Cache.init(policy:storagePolicy:clock:)` is renamed `init(policy:storageEngine:clock:)`.
- `Cache.evictUntil(maxNbItems:)` is renamed `evictUntil(maxCount:)`.
- `CacheableDataType` is removed; use `Sendable`.
- The `Cache` subscript setter is removed, since code outside the cache can't call it. Use `add(_:for:expiresAfter:)` and `remove(_:)`.
- `StringDiskStorageSerializer<NSString>` is replaced by `TextDiskStorageSerializer`, and `StringDiskStorageSerializerError` is renamed `TextDiskStorageSerializerError`.

### Fixed

- Keys longer than about 190 bytes could not be persisted on Linux, because their filenames exceeded the file-system limit.
- `DiskStorageEngine.persist(_:)` produced an unused-result warning.

## [1.1.1] - 2026-09-05

### Fixed

- Every read API persists the entry's access time.
- Disk storage honors the configured writing options.
- Disk timestamps keep fractional seconds. Older releases can't read the new numeric format.
- Unicode-equivalent disk keys share one file, and entries stored under earlier spellings are migrated.
- `StringDiskStorageSerializer` throws when a string can't be represented in its encoding.

### Changed

- `CacheEntry.value` is no longer optional.
- Expired entries are found with a linear scan instead of a sort.

## [1.1.0] - 2026-08-20

### Added

- Typed cache keys through the `CacheKey` protocol.

## [1.0.0] - 2026-08-19

Initial release.

[Unreleased]: https://github.com/modern-swift-dev/swift-stash/compare/1.1.1...HEAD
[1.1.1]: https://github.com/modern-swift-dev/swift-stash/compare/1.1.0...1.1.1
[1.1.0]: https://github.com/modern-swift-dev/swift-stash/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/modern-swift-dev/swift-stash/releases/tag/1.0.0
