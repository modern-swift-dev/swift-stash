---
title: "Getting started | SwiftStash"
description: "Install SwiftStash and create an actor-isolated cache."
---

<a id="main-content"></a>

Getting started

# Put a value in the cache. Read it back with await.

Start with memory storage. Move to disk when an entry needs to survive beyond the cache actor.

## Requirements

- Swift 6.0 or later

- macOS 15, iOS 17, tvOS 17, watchOS 10, or visionOS 1 or later

## Install {{version}}

Add SwiftStash to the package dependencies in `Package.swift`. Then add `"SwiftStash"` to the dependencies of your target.

Package.swift

```swift
.package(
    url: "https://github.com/modern-swift-dev/swift-stash.git",
    from: "{{version}}"
)
```

## First cache entry

`Cache` is an actor. The cache accepts values that conform to `Sendable`. A string-backed enum gets the required `CacheKey` behavior automatically.

Swift

```swift
import SwiftStash

enum ProfileKey: String, CacheKey {
    case current
}

let storage = MemoryStorageEngine<ProfileKey, String>()
let cache = await Cache(storagePolicy: storage)

await cache.add("Ada", for: .current)
let currentProfile = await cache[.current]
```

## Persist entries to disk

Create the named directory before persistence begins. `DiskStorageEngine` writes each entry below the app cache directory and does not create the named subdirectory for you.

Swift

```swift
let storage = DiskStorageEngine(
    directory: "profiles",
    keyType: ProfileKey.self,
    serializer: JsonDiskStorageSerializer<Profile>()
)
let cache = await Cache(storagePolicy: storage)
```

<a id="eviction"></a>

## Compare cache state after eviction

Choose `.fifo`, `.lifo`, or `.lru` when creating the cache. Call `evictExpired()` to remove old entries, or call `evictUntil(maxNbItems:)` to first remove expired entries and then enforce a maximum count.

SwiftStash does not run a background timer. Place the eviction call in the workflow that knows when reducing the cache makes sense.

<a id="comparison-title"></a>

## Compare cache records before and after a count limit

### Before

`concurrency` A tour of Swift concurrency

`actors` Protecting state with actors

2 entries

### After `evictUntil(maxNbItems: 1)`

`concurrency` A tour of Swift concurrency

1 entry
