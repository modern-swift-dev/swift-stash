---
title: "Documentation | SwiftStash"
description: "Guides and API reference for SwiftStash."
---

<a id="main-content"></a>

Documentation

# Learn the cache, then decide when it should evict.

SwiftStash has a narrow API. The guide covers installation, memory caches, disk persistence, and the eviction methods that change cache state.

## [Getting started](/docs/swift-stash/documentation/getting-started/)

Check requirements, add the package, create a cache, and make the first read.

## [Memory storage](/docs/swift-stash/examples/#memory-cache)

Use MemoryStorageEngine when values should last only as long as the cache actor.

## [Disk storage](/docs/swift-stash/examples/#disk-cache)

Persist Codable data with JSON or bring your own DiskStorageSerializer.

## [Eviction](/docs/swift-stash/documentation/getting-started/#eviction)

Compare FIFO, LIFO, and LRU, then call eviction at the point your app chooses.

## [Examples](/docs/swift-stash/examples/)

Copy from independent executable Swift packages in the repository.

## [API reference](/docs/swift-stash/api/documentation/swiftstash/)

Generated documentation for public cache, storage, serializer, and key types.

[Open API reference](/docs/swift-stash/api/documentation/swiftstash/)
