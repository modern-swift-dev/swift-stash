---
title: "SwiftStash | A cache for modern Swift"
description: "SwiftStash is a small actor-isolated cache with memory and disk storage engines for Swift 6."
---

<a id="main-content"></a>

Swift 6 cache library

# Cache Swift values inside an actor.

SwiftStash is an actor-isolated cache with explicit FIFO, LIFO, and LRU eviction. Use a no-op memory engine for process-local values or persist entries to disk with a serializer you control.

[Read the guide](/docs/swift-stash/documentation/getting-started/) [See runnable examples](/docs/swift-stash/examples/)

No background timer. You decide when eviction runs.

## Latest release

<a id="release-title"></a>

{{version}}

Published {{releaseDate}}

[Read release notes]({{releaseURL}})

## Install {{version}}

Add the package to your `Package.swift`, then add `"SwiftStash"` to the target dependencies that use it.

Package.swift

```swift
dependencies: [
    .package(
        url: "https://github.com/modern-swift-dev/swift-stash.git",
        from: "{{version}}"
    )
]
```

A small first cache

## Store and read a value through the actor.

Calls that cross the cache actor use `await`. Cached values need to conform to `Sendable`.

Swift

```swift
import SwiftStash

let storage = MemoryStorageEngine<String, String>()
let cache = await Cache(
    policy: .lru(threshold: 5 * 60),
    storagePolicy: storage
)

await cache.add("Ada", for: "current-user")
let name = await cache["current-user"]
```

What it does

## Choose storage and control eviction.

### Actor isolation

`Cache` is an actor. Reads, writes, and eviction happen inside its isolation domain.

### Explicit eviction

Set a FIFO, LIFO, or LRU policy, then call `evictExpired()` or `evictUntil(maxNbItems:)`.

### Storage you choose

Use memory when persistence does not matter. Use disk with JSON, strings, or a custom serializer when it does.

<a id="comparison-title"></a>

## An explicit eviction changes the cache

### Before

`concurrency` A tour of Swift concurrency

`actors` Protecting state with actors

2 entries

### After `evictUntil(maxNbItems: 1)`

`concurrency` A tour of Swift concurrency

1 entry

Platforms and source

## Built as a Swift package.

SwiftStash is MIT-licensed. Its source, issues, releases, and package metadata are public in the modern-swift-dev GitHub organization.

- macOS 15+

- iOS 17+

- tvOS 17+

- watchOS 10+

- visionOS 1+

- Linux with Swift 6+

## [Documentation](/docs/swift-stash/documentation/)

Start with the guide, then choose a storage engine and eviction policy.

## [API reference](/docs/swift-stash/api/documentation/swiftstash/)

Browse generated Swift API documentation for the SwiftStash module.

## [MIT source on GitHub](https://github.com/modern-swift-dev/swift-stash)

Inspect the package and its license, report an issue, or review published releases.

[Open repository](https://github.com/modern-swift-dev/swift-stash)
