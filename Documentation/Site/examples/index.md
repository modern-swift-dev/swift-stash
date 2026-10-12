---
title: "Examples | SwiftStash"
description: "Runnable SwiftStash examples for memory caches, disk caches, encrypted disk caches, and custom serializers."
---

<a id="main-content"></a>

Examples

# Read the complete executable examples.

Each example is a standalone Swift package. Run it from the repository after moving into its directory or passing its path to SwiftPM.

## Memory cache

Use a typed enum key and an identifiable `Sendable` value. The identifiable overload uses the value's ID as its cache key.

MemoryCacheExample

<!-- include: Examples/memory-cache/Sources/MemoryCacheExample/main.swift -->

<a id="disk-cache"></a>

## Disk cache with JSON

The JSON serializer stores a `Codable` profile, and the cache reads the profile through its string ID.

DiskCacheExample

<!-- include: Examples/disk-cache/Sources/DiskCacheExample/main.swift -->

<a id="encrypted-disk-cache"></a>

## Encrypted disk cache

An encryption key encrypts each entry file. On platforms without CryptoKit, the package adds swift-crypto for `SymmetricKey`, as [Encrypting entries on disk](/docs/swift-stash/documentation/encrypting-entries-on-disk/) shows.

EncryptedDiskCacheExample

<!-- include: Examples/encrypted-disk-cache/Sources/EncryptedDiskCacheExample/main.swift -->

<a id="custom-serializer"></a>

## Custom disk serializer

A serializer converts one stored type to `Data` and back. This example persists a temperature as an eight-byte value.

CustomSerializerExample

<!-- include: Examples/custom-serializer/Sources/CustomSerializerExample/main.swift -->
