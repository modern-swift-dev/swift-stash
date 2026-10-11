import Foundation
@testable import SwiftStash
import Testing

/// A UTF-8 serializer that counts deserializations, to observe when values are read from disk.
private final class CountingSerializer: DiskStorageSerializer, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var serializations = 0

    var deserializeCount: Int {
        lock.withLock { count }
    }

    var serializeCount: Int {
        lock.withLock { serializations }
    }

    func serialize(_ value: String) throws -> Data {
        lock.withLock { serializations += 1 }
        return Data(value.utf8)
    }

    func deserialize(_ data: Data) throws -> String? {
        lock.withLock { count += 1 }
        return String(data: data, encoding: .utf8)
    }
}

struct LazyLoadingTests {
    private let clock = ManualClock(now: Date(timeIntervalSince1970: 1_746_364_519))
    private let directories = TestDirectories()

    private typealias LazyCache = Cache<DiskStorageEngine<String, String, CountingSerializer>>

    /// Stores entries in a new directory and returns its name.
    private func storeEntries(_ entries: [String: String], costLimit: CostLimit<String>? = nil) async -> String {
        let directory = directories.make("TestLazyLoading")
        let cache = Cache(
            policy: .fifo(threshold: 300),
            storageEngine: DiskStorageEngine(directory: directory, serializer: CountingSerializer()),
            clock: clock,
            costLimit: costLimit
        )
        await cache.add(entries.map { ($0.key, $0.value) })
        return directory
    }

    private func reopen(
        _ directory: String,
        serializer: CountingSerializer,
        policy: EvictionPolicy = .fifo(threshold: 300),
        costLimit: CostLimit<String>? = nil
    ) -> LazyCache {
        Cache(
            policy: policy,
            storageEngine: DiskStorageEngine(directory: directory, serializer: serializer),
            clock: clock,
            costLimit: costLimit
        )
    }

    @Test func creatingACacheDoesNotReadValues() async {
        let directory = await storeEntries(["a": "one", "b": "two", "c": "three"])
        let serializer = CountingSerializer()

        let cache = reopen(directory, serializer: serializer)

        #expect(await cache.count == 3)
        #expect(await cache.contains("a"))
        #expect(serializer.deserializeCount == 0)
    }

    @Test func valuesAreReadOnceOnFirstUse() async {
        let directory = await storeEntries(["a": "one", "b": "two"])
        let serializer = CountingSerializer()
        let cache = reopen(directory, serializer: serializer)

        #expect(await cache["a"] == "one")
        #expect(await cache["a"] == "one")
        #expect(await cache.entry(for: "a")?.value == "one")
        #expect(serializer.deserializeCount == 1)

        #expect(Set(await cache.values()) == ["one", "two"])
        #expect(serializer.deserializeCount == 2)
    }

    @Test func unloadValuesReleasesValuesThatCanBeReloaded() async {
        let directory = await storeEntries(["a": "one"])
        let serializer = CountingSerializer()
        let cache = reopen(directory, serializer: serializer)
        #expect(await cache["a"] == "one")

        await cache.unloadValues()

        #expect(await cache.count == 1)
        #expect(await cache["a"] == "one")
        #expect(serializer.deserializeCount == 2)
    }

    @Test func unloadValuesKeepsValuesThatCannotBeReloaded() async {
        let cache = Cache(storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("value", for: "key")

        await cache.unloadValues()

        #expect(await cache["key"] == "value")
    }

    @Test func removingAndEvictingUnloadedEntriesDeletesTheirFilesWithoutReadingThem() async {
        let directory = await storeEntries(["a": "one", "b": "two", "c": "three"])
        let serializer = CountingSerializer()
        let cache = reopen(directory, serializer: serializer)

        await cache.remove("a")
        await cache.evictUntil(maxCount: 1)

        #expect(serializer.deserializeCount == 0)
        #expect(await cache.keys() == ["c"])
        let reopened = reopen(directory, serializer: CountingSerializer())
        #expect(await reopened.keys() == ["c"])
    }

    @Test func expiredUnloadedEntriesAreRemovedWithoutReadingThem() async {
        let directory = await storeEntries(["a": "one"])
        let serializer = CountingSerializer()
        let cache = reopen(directory, serializer: serializer, policy: .fifo(threshold: 10))
        clock.advance(by: 10)

        #expect(await cache["a"] == nil)
        #expect(serializer.deserializeCount == 0)
        #expect(await reopen(directory, serializer: CountingSerializer()).isEmpty)
    }

    @Test func unreadableValuesAreRemovedWhenRead() async throws {
        let directory = await storeEntries(["a": "one", "b": "two"])
        let cache = reopen(directory, serializer: CountingSerializer())
        let file = URL.swiftStashCacheDirectory.appendingPathComponent(directory).appendingPathComponent("a".cacheEntryFileName)
        try FileManager.default.removeItem(at: file)

        #expect(await cache["a"] == nil)
        #expect(await cache.keys() == ["b"])
    }

    @Test func storedCostsAreUsedWithoutReadingValues() async {
        let limit = CostLimit<String>(maxCost: 100) { $0.count }
        let directory = await storeEntries(["a": "one", "b": "three"], costLimit: limit)
        let serializer = CountingSerializer()

        let cache = reopen(directory, serializer: serializer, costLimit: limit)

        #expect(await cache.totalCost == 8)
        #expect(serializer.deserializeCount == 0)
    }

    @Test func entriesStoredWithoutACostAreReadToComputeIt() async {
        let directory = await storeEntries(["a": "one", "b": "three"])
        let serializer = CountingSerializer()

        let cache = reopen(directory, serializer: serializer, costLimit: CostLimit(maxCost: 100) { $0.count })

        #expect(await cache.totalCost == 8)
        #expect(serializer.deserializeCount == 2)
        #expect(await cache["a"] == "one")
        #expect(serializer.deserializeCount == 2)
    }

    @Test func diskEngineLoadsMetadataWithoutValues() throws {
        let directory = directories.make("TestLoadMetadata")
        let serializer = CountingSerializer()
        let engine = DiskStorageEngine(directory: directory, serializer: serializer)
        let date = Date(timeIntervalSince1970: 1000)
        engine.persist(CacheEntry(key: "key", value: "value", creation: date, lastAccess: date, accessCount: 2, cost: 5))

        let reopened = DiskStorageEngine(directory: directory, serializer: serializer)
        let metadata = try #require(reopened.loadMetadata()?.first)

        #expect(metadata.key == "key")
        #expect(metadata.creation == date)
        #expect(metadata.accessCount == 2)
        #expect(metadata.cost == 5)
        #expect(serializer.deserializeCount == 0)
        #expect(reopened.loadValue(for: "key") == "value")
        #expect(reopened.loadValue(for: "missing") == nil)
    }

    @Test func enginesLoadEagerlyByDefault() {
        let engine = MemoryStorageEngine<String, String>()
        let date = Date(timeIntervalSince1970: 1000)

        #expect(engine.loadMetadata() == nil)
        #expect(engine.loadValue(for: "key") == nil)
        #expect(!engine.persistMetadata(CacheEntryMetadata(key: "key", creation: date, lastAccess: date)))
    }

    // MARK: - Metadata Updates

    private func fileURL(for key: String, in directory: String) -> URL {
        URL.swiftStashCacheDirectory.appendingPathComponent(directory).appendingPathComponent(key.cacheEntryFileName)
    }

    @Test func lruReadsUpdateMetadataWithoutRewritingValues() async throws {
        let directory = await storeEntries(["a": "one"])
        let sizeBefore = try Data(contentsOf: fileURL(for: "a", in: directory)).count
        let serializer = CountingSerializer()
        let cache = reopen(directory, serializer: serializer, policy: .lru(threshold: 300))

        clock.advance(by: 5)
        #expect(await cache["a"] == "one")
        clock.advance(by: 5)
        #expect(await cache["a"] == "one")

        #expect(serializer.serializeCount == 0)
        #expect(try Data(contentsOf: fileURL(for: "a", in: directory)).count == sizeBefore)
        let metadata = try #require(DiskStorageEngine(directory: directory, serializer: CountingSerializer()).loadMetadata()?.first)
        #expect(metadata.accessCount == 2)
        #expect(metadata.lastAccess == clock.now)
    }

    @Test func headersWithoutRoomAreRewrittenAroundTheValue() async throws {
        let directory = await storeEntries(["a": "one"])
        let url = fileURL(for: "a", in: directory)
        // Remove the header padding so the updated header can't be written in place.
        let file = try Data(contentsOf: url)
        let regionLength = file[4 ..< 8].reduce(0) { $0 << 8 | Int($1) }
        var header = Data(file[8 ..< 8 + regionLength])
        while header.last == UInt8(ascii: " ") {
            header.removeLast()
        }
        var compact = Data("SSE2".utf8)
        withUnsafeBytes(of: UInt32(header.count).bigEndian) { compact.append(contentsOf: $0) }
        try (compact + header + file[(8 + regionLength)...]).write(to: url)
        let serializer = CountingSerializer()
        let cache = reopen(directory, serializer: serializer, policy: .lru(threshold: 300))

        clock.advance(by: 5)
        #expect(await cache["a"] == "one")

        #expect(serializer.serializeCount == 0)
        let reopened = DiskStorageEngine(directory: directory, serializer: CountingSerializer())
        #expect(reopened.loadMetadata()?.first?.accessCount == 1)
        #expect(reopened.loadValue(for: "a") == "one")
    }

    @Test func persistMetadataFailsWithoutAnEntryFile() {
        let engine = DiskStorageEngine(directory: directories.make("TestMissingMetadata"), serializer: CountingSerializer())
        let date = Date(timeIntervalSince1970: 1000)

        #expect(!engine.persistMetadata(CacheEntryMetadata(key: "missing", creation: date, lastAccess: date)))
    }

    @Test func persistMetadataRespectsWithoutOverwriting() {
        let engine = DiskStorageEngine<String, String, CountingSerializer>(
            directory: directories.make("TestMetadataWithoutOverwriting"),
            serializer: CountingSerializer(),
            options: [.withoutOverwriting]
        )
        let date = Date(timeIntervalSince1970: 1000)
        let entry = CacheEntry(key: "key", value: "value", creation: date, lastAccess: date)
        #expect(engine.persist(entry))

        var metadata = entry.metadata
        metadata.updateLastAccess(at: date.addingTimeInterval(1))

        #expect(!engine.persistMetadata(metadata))
        #expect(engine.loadMetadata()?.first?.lastAccess == date)
    }
}
