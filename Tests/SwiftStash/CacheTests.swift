import Foundation
@testable import SwiftStash
import Testing

struct CacheTests {

    // MARK: - Test Data Structures

    private struct TestItem: Sendable, Identifiable, Equatable, ExpressibleByStringLiteral {
        let id: String
        let value: String

        init(id: String, value: String) {
            self.id = id
            self.value = value
        }

        init(stringLiteral value: StringLiteralType) {
            self.id = UUID().uuidString
            self.value = value
        }
    }

    private enum TestKey: String, CacheKey, CaseIterable {
        case first
        case second
        case third
    }

    private struct KeyedTestItem: Sendable, Identifiable, Equatable {
        let id: TestKey
        let value: String
    }

    private let clock = ManualClock(now: Date(timeIntervalSince1970: 1_746_364_519))

    @Test func fifoEvictionByThreshold() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .fifo(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add items individually
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "3", value: "third"))
        clock.advance(by: 15)

        // Evict expired
        await cache.evictExpired()

        // Should have evicted all items
        let isEmpty = await cache.isEmpty
        #expect(isEmpty)
    }

    @Test func fifoEvictionByCount() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .fifo(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add items individually
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "3", value: "third"))
        clock.advance(by: 1)

        // Evict until only 1 remains
        await cache.evictUntil(maxCount: 1)

        // Should have 1 item - the last one added (since FIFO removes oldest first)
        let count = await cache.count
        let lastItem = await cache["3"]
        #expect(count == 1)
        #expect(lastItem != nil)
    }

    // MARK: - LIFO Tests

    @Test func lifoEvictionByThreshold() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .fifo(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add first two items
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 15)
        await cache.add(TestItem(id: "3", value: "third"))

        // Evict expired (should remove items 1 and 2 since they're older than threshold)
        await cache.evictExpired()

        // Should have only item 3 remaining since it was added after the wait
        let count = await cache.count
        let lastItem = await cache["3"]
        #expect(count == 1)
        #expect(lastItem != nil)
    }

    @Test func lifoEvictionByCount() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lifo(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add items individually
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "3", value: "third"))
        clock.advance(by: 1)

        // Evict until only 1 remains
        await cache.evictUntil(maxCount: 1)

        // Should have 1 item - the first one added (since LIFO removes newest first)
        let count = await cache.count
        let firstItem = await cache["1"]
        #expect(count == 1)
        #expect(firstItem != nil)
    }

    // MARK: - LRU Tests

    @Test func lruEvictionByThreshold() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add items individually
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "3", value: "third"))
        clock.advance(by: 12)

        // Access item "2" before it expires to make it most recently used
        _ = await cache["2"]
        clock.advance(by: 4)

        await cache.evictExpired()

        // Should have evicted all except most recently used
        let count = await cache.count
        let item = await cache["2"]
        #expect(count == 1)
        #expect(item != nil)
    }

    @Test func lruEvictionByCount() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add items individually
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "3", value: "third"))
        clock.advance(by: 5)

        // Access items in specific order
        _ = await cache["1"]
        clock.advance(by: 1)
        _ = await cache["3"]
        clock.advance(by: 1)

        // Evict until only 1 remains
        await cache.evictUntil(maxCount: 1)

        // Should keep most recently accessed item
        let count = await cache.count
        let item = await cache["3"]
        #expect(count == 1)
        #expect(item != nil)
    }

    // MARK: - Cache Utility Methods Tests

    @Test func keysReturnsAllKeys() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "a", value: "first"), for: "a")
        await cache.add(TestItem(id: "b", value: "second"), for: "b")
        await cache.add(TestItem(id: "c", value: "third"), for: "c")

        let keys = await cache.keys()
        #expect(keys.sorted() == ["a", "b", "c"])
    }

    @Test func valuesReturnsAllValues() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "1", value: "first"), for: "1")
        await cache.add(TestItem(id: "2", value: "second"), for: "2")

        let values = await cache.values()
        #expect(values.count == 2)
        #expect(values.contains { $0.value == "first" })
        #expect(values.contains { $0.value == "second" })
    }

    @Test func entryReturnsEntryAndUpdatesAccess() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "key1", value: "value1"), for: "key1")

        let entry = await cache.entry(for: "key1")
        #expect(entry != nil)
        #expect(entry?.key == "key1")
        #expect(entry?.value.value == "value1")
    }

    private enum ReadMethod: CaseIterable {
        case subscriptValue
        case entry
    }

    @Test func readsPersistAccessAcrossReload() async throws {
        for method in ReadMethod.allCases {
            let directory = directories.make("TestReadPersistence")
            let directoryURL = URL.swiftStashCacheDirectory.appendingPathComponent(directory)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let storage = DiskStorageEngine<String, String, TextDiskStorageSerializer>(
                directory: directory,
                serializer: TextDiskStorageSerializer()
            )
            let cache = Cache(policy: .lru(threshold: 10), storageEngine: storage, clock: clock)
            await cache.add([("first", "one"), ("second", "two")])
            clock.advance(by: 9)

            switch method {
                case .subscriptValue:
                    #expect(await cache["first"] == "one")
                case .entry:
                    #expect(await cache.entry(for: "first")?.value == "one")
            }

            clock.advance(by: 2)
            let reloaded = Cache(
                policy: .lru(threshold: 10),
                storageEngine: DiskStorageEngine<String, String, TextDiskStorageSerializer>(
                    directory: directory,
                    serializer: TextDiskStorageSerializer()
                ),
                clock: clock
            )
            await reloaded.evictExpired()
            #expect(await reloaded.keys() == ["first"])

            // The access extends the lifetime only until its own threshold boundary.
            clock.advance(by: 8)
            await reloaded.evictExpired()
            #expect(await reloaded.isEmpty)
        }
    }

    @Test func expirationIncludesThresholdBoundaryForEveryPolicy() async {
        typealias TestCache = Cache<MemoryStorageEngine<String, String>, String>
        let caches = [
            TestCache(policy: .fifo(threshold: 10), storageEngine: MemoryStorageEngine(), clock: clock),
            TestCache(policy: .lifo(threshold: 10), storageEngine: MemoryStorageEngine(), clock: clock),
            TestCache(policy: .lru(threshold: 10), storageEngine: MemoryStorageEngine(), clock: clock)
        ]
        for cache in caches {
            await cache.add("old", for: "expired")
            clock.advance(by: 1)
            await cache.add("new", for: "retained")
            clock.advance(by: 9)

            await cache.evictExpired()

            #expect(await cache.keys() == ["retained"])
        }
    }

    private let directories = TestDirectories()

    /// The eviction policies, each with a 10-second threshold.
    static let policies: [EvictionPolicy] = [.fifo(threshold: 10), .lifo(threshold: 10), .lru(threshold: 10)]

    @Test func nestedEvictionPolicyNameRefersToTheSharedType() {
        let nested: Cache<MemoryStorageEngine<String, String>, String>.EvictionPolicy = .lru(threshold: 10)
        let shared: EvictionPolicy = nested
        #expect(shared == .lru(threshold: 10))
        #expect(shared != .fifo(threshold: 10))
    }

    @Test(arguments: Self.policies) func subscriptDoesNotReturnExpiredValues(
        policy: EvictionPolicy
    ) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("value", for: "key")
        clock.advance(by: 10)

        #expect(await cache["key"] == nil)
        #expect(await cache.isEmpty)
    }

    @Test(arguments: Self.policies) func entryDoesNotReturnExpiredEntries(
        policy: EvictionPolicy
    ) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("value", for: "key")
        clock.advance(by: 10)

        #expect(await cache.entry(for: "key") == nil)
        #expect(await cache.isEmpty)
    }

    @Test(arguments: Self.policies) func valuesSkipsExpiredValues(
        policy: EvictionPolicy
    ) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("old", for: "expired")
        clock.advance(by: 5)
        await cache.add("new", for: "fresh")
        clock.advance(by: 5)

        #expect(await cache.values() == ["new"])
        #expect(await cache.keys() == ["fresh"])
    }

    @Test(arguments: Self.policies) func valuesReadJustBeforeExpiryAreReturned(
        policy: EvictionPolicy
    ) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("value", for: "key")
        clock.advance(by: 9.999)

        #expect(await cache["key"] == "value")
    }

    @Test func expiredReadRemovesTheEntryFromStorage() async {
        let directory = directories.make("TestExpiredRead")
        let storage = DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer())
        let cache = Cache(policy: .fifo(threshold: 10), storageEngine: storage, clock: clock)
        await cache.add("value", for: "key")
        clock.advance(by: 10)

        #expect(await cache["key"] == nil)

        let reloaded = DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer())
        #expect(reloaded.load().isEmpty)
    }

    @Test(arguments: Self.policies) func evictionBreaksDateTiesByKey(policy: EvictionPolicy) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add(["c", "a", "e", "b", "d"].map { ($0, $0) })

        await cache.evictUntil(maxCount: 2)

        let expected: [String] = switch policy {
            case .fifo,
                 .lru: ["d", "e"]
            case .lifo: ["a", "b"]
        }
        #expect(await cache.keys().sorted() == expected)
    }

    /// A storage engine that counts persisted entries.
    private final class CountingStorageEngine: StorageEngine, @unchecked Sendable {
        private(set) var persistCount = 0

        func load() -> [CacheEntry<String, String>] {
            []
        }

        func delete(_: CacheEntry<String, String>) {}
        func persist(_: CacheEntry<String, String>) -> Bool {
            persistCount += 1
            return true
        }

        func clear() {}
    }

    @Test(arguments: Self.policies) func readsPersistAccessOnlyForLRU(policy: EvictionPolicy) async {
        let storage = CountingStorageEngine()
        let cache = Cache(policy: policy, storageEngine: storage, clock: clock)
        await cache.add("one", for: "first")
        await cache.add("two", for: "second")
        #expect(storage.persistCount == 2)

        _ = await cache["first"]
        _ = await cache.entry(for: "first")
        _ = await cache.values()

        #expect(storage.persistCount == (policy == .lru(threshold: 10) ? 4 : 2))
    }

    @Test(arguments: Self.policies) func containsReportsUnexpiredEntries(policy: EvictionPolicy) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("value", for: "key")

        #expect(await cache.contains("key"))
        #expect(await !cache.contains("missing"))

        clock.advance(by: 10)
        #expect(await !cache.contains("key"))
    }

    @Test func containsDoesNotRecordAccess() async {
        let storage = CountingStorageEngine()
        let cache = Cache(policy: .lru(threshold: 10), storageEngine: storage, clock: clock)
        await cache.add("one", for: "first")
        clock.advance(by: 1)
        await cache.add("two", for: "second")
        clock.advance(by: 1)

        #expect(await cache.contains("first"))
        await cache.evictUntil(maxCount: 1)

        #expect(storage.persistCount == 2)
        #expect(await cache.keys() == ["second"])
    }

    @Test func lruAccessCountSurvivesReload() async {
        let directory = directories.make("TestAccessCountReload")
        let cache = Cache(
            policy: .lru(threshold: 300),
            storageEngine: DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer()),
            clock: clock
        )
        await cache.add("value", for: "key")
        _ = await cache["key"]
        _ = await cache["key"]

        let reloaded = Cache(
            policy: .lru(threshold: 300),
            storageEngine: DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer()),
            clock: clock
        )
        #expect(await reloaded.entry(for: "key")?.accessCount == 3)
    }

    @Test func initIsSynchronousAndLoadsStoredEntries() async {
        let directory = directories.make("TestSynchronousInit")
        let storage = DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer())
        storage.persist(CacheEntry(key: "key", value: "value", creation: clock.now, lastAccess: clock.now))

        let cache = makeCacheSynchronously(directory: directory)

        #expect(await cache["key"] == "value")
    }

    private func makeCacheSynchronously(directory: String) -> Cache<DiskStorageEngine<String, String, TextDiskStorageSerializer>, String> {
        Cache(
            storageEngine: DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer()),
            clock: clock
        )
    }

    @Test(arguments: Self.policies) func addEnforcesMaxCount(policy: EvictionPolicy) async {
        let cache = Cache(policy: policy, storageEngine: MemoryStorageEngine<String, String>(), clock: clock, maxCount: 2)
        for key in ["a", "b", "c"] {
            await cache.add(key, for: key)
            clock.advance(by: 1)
        }

        let expected: [String] = switch policy {
            case .fifo,
                 .lru: ["b", "c"]
            case .lifo: ["a", "b"]
        }
        #expect(await cache.keys().sorted() == expected)
    }

    @Test func batchAddEnforcesMaxCount() async {
        let cache = Cache(policy: .fifo(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: clock, maxCount: 3)
        await cache.add("old", for: "old")
        clock.advance(by: 1)

        await cache.add(["c", "a", "e", "b", "d"].map { ($0, $0) })

        #expect(await cache.keys().sorted() == ["c", "d", "e"])
    }

    @Test func maxCountRemovesExpiredEntriesFirst() async {
        // By count alone, LIFO would evict the new entry; the expired one goes first instead.
        let cache = Cache(policy: .lifo(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: clock, maxCount: 2)
        await cache.add("old", for: "old")
        clock.advance(by: 5)
        await cache.add("recent", for: "recent")
        clock.advance(by: 5)

        await cache.add("new", for: "new")

        #expect(await cache.keys().sorted() == ["new", "recent"])
    }

    @Test func withoutMaxCountAddKeepsEveryEntry() async {
        let cache = Cache(policy: .fifo(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add((0 ..< 100).map { ("\($0)", "\($0)") })

        #expect(await cache.count == 100)
    }

    @Test func valuesDoesNotChangeLRUOrder() async {
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        // "b" is older, but sorts after "a", so a tie in access dates would evict "a".
        await cache.add("older", for: "b")
        clock.advance(by: 1)
        await cache.add("newer", for: "a")
        clock.advance(by: 1)

        #expect(Set(await cache.values()) == ["older", "newer"])
        clock.advance(by: 1)
        await cache.evictUntil(maxCount: 1)

        #expect(await cache.keys() == ["a"])
    }

    @Test func valuesDoesNotExtendLRULifetimes() async {
        let cache = Cache(policy: .lru(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("value", for: "key")
        clock.advance(by: 9)
        #expect(await cache.values() == ["value"])

        clock.advance(by: 1)

        #expect(await cache.values().isEmpty)
        #expect(await cache.isEmpty)
    }

    @Test func entryReturnsNilForMissingKey() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        let entry = await cache.entry(for: "nonexistent")
        #expect(entry == nil)
    }

    @Test func removeDeletesEntry() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "key1", value: "value1"), for: "key1")
        await cache.add(TestItem(id: "key2", value: "value2"), for: "key2")

        await cache.remove("key1")

        let count = await cache.count
        let removedItem = await cache["key1"]
        let remainingItem = await cache["key2"]

        #expect(count == 1)
        #expect(removedItem == nil)
        #expect(remainingItem != nil)
    }

    @Test func removeNonexistentKeyDoesNothing() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "key1", value: "value1"), for: "key1")
        await cache.remove("nonexistent")

        let count = await cache.count
        #expect(count == 1)
    }

    @Test func clearRemovesAllEntries() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "1", value: "first"), for: "1")
        await cache.add(TestItem(id: "2", value: "second"), for: "2")
        await cache.add(TestItem(id: "3", value: "third"), for: "3")

        await cache.clear()

        let isEmpty = await cache.isEmpty
        let count = await cache.count
        #expect(isEmpty)
        #expect(count == 0)
    }

    // MARK: - Batch Add and Subscript Tests

    @Test func batchAddMultipleValues() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add([
            ("a", TestItem(id: "a", value: "first")),
            ("b", TestItem(id: "b", value: "second")),
            ("c", TestItem(id: "c", value: "third"))
        ])

        let count = await cache.count
        let itemA = await cache["a"]
        let itemB = await cache["b"]
        let itemC = await cache["c"]

        #expect(count == 3)
        #expect(itemA?.value == "first")
        #expect(itemB?.value == "second")
        #expect(itemC?.value == "third")
    }

    // MARK: - EvictUntil Edge Cases

    @Test func evictUntilZeroClearsCache() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "1", value: "first"), for: "1")
        await cache.add(TestItem(id: "2", value: "second"), for: "2")

        let remaining = await cache.evictUntil(maxCount: 0)

        #expect(remaining == 0)
        let isEmpty = await cache.isEmpty
        #expect(isEmpty)
    }

    @Test func evictUntilWhenUnderMaxReturnsCount() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "1", value: "first"), for: "1")
        await cache.add(TestItem(id: "2", value: "second"), for: "2")

        let remaining = await cache.evictUntil(maxCount: 10)

        #expect(remaining == 2)
    }

    // MARK: - Identifiable Extension Test

    @Test func addIdentifiableUsesIdAsKey() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lru(threshold: 300), storageEngine: storage, clock: clock)

        let item = TestItem(id: "myId", value: "myValue")
        await cache.add(item)

        let retrieved = await cache["myId"]
        #expect(retrieved?.id == "myId")
        #expect(retrieved?.value == "myValue")
    }

    // MARK: - Typed Key Tests

    @Test func enumKeyOperationsUseTheDeclaredKeyType() async {
        let storage = MemoryStorageEngine<TestKey, TestItem>()
        let cache = Cache(storageEngine: storage, clock: clock)

        await cache.add([
            (.first, TestItem(id: "1", value: "first")),
            (.second, TestItem(id: "2", value: "second"))
        ])
        await cache.add(TestItem(id: "3", value: "third"), for: .third)

        let keys = await cache.keys()
        let entry = await cache.entry(for: .first)
        let third = await cache[.third]

        #expect(Set(keys) == Set(TestKey.allCases))
        #expect(entry?.key == .first)
        #expect(entry?.value.value == "first")
        #expect(third?.value == "third")

        await cache.remove(.second)
        await cache.remove(.third)

        #expect(await cache[.second] == nil)
        #expect(await cache[.third] == nil)
        #expect(await cache.keys() == [.first])
    }

    @Test func enumKeyParticipatesInEviction() async {
        let storage = MemoryStorageEngine<TestKey, TestItem>()
        let cache = Cache(policy: .fifo(threshold: 300), storageEngine: storage, clock: clock)

        await cache.add(TestItem(id: "1", value: "first"), for: .first)
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"), for: .second)

        let remaining = await cache.evictUntil(maxCount: 1)

        #expect(remaining == 1)
        #expect(await cache[.first] == nil)
        #expect(await cache[.second]?.value == "second")
    }

    @Test func identifiableValueUsesMatchingEnumId() async {
        let storage = MemoryStorageEngine<TestKey, KeyedTestItem>()
        let cache = Cache(storageEngine: storage, clock: clock)
        let item = KeyedTestItem(id: .second, value: "value")

        let entry = await cache.add(item)

        #expect(entry.key == .second)
        #expect(await cache[.second] == item)
    }

    // MARK: - LIFO Threshold Test (Corrected)

    @Test func lifoEvictionByThresholdCorrect() async {
        let storage = MemoryStorageEngine<String, TestItem>()
        let cache = Cache(policy: .lifo(threshold: 15.0), storageEngine: storage, clock: clock)

        // Add first two items
        await cache.add(TestItem(id: "1", value: "first"))
        clock.advance(by: 1)
        await cache.add(TestItem(id: "2", value: "second"))
        clock.advance(by: 15)
        await cache.add(TestItem(id: "3", value: "third"))

        // Evict expired (should remove items 1 and 2 since they're older than threshold)
        await cache.evictExpired()

        // Should have only item 3 remaining since it was added after the wait
        let count = await cache.count
        let lastItem = await cache["3"]
        #expect(count == 1)
        #expect(lastItem != nil)
    }
}

/// Calls deprecated API through a protocol so the tests compile without deprecation warnings.
private protocol DeprecatedCacheAPI {
    func makeCache() -> Cache<MemoryStorageEngine<String, String>, String>
    func evictUntil(maxNbItems: Int, in cache: Cache<MemoryStorageEngine<String, String>, String>) async -> Int
    func isCacheable(_ type: (some Sendable).Type) -> Bool
}

private struct DeprecatedCacheAPICalls: DeprecatedCacheAPI {
    @available(*, deprecated)
    func makeCache() -> Cache<MemoryStorageEngine<String, String>, String> {
        Cache(policy: .fifo(threshold: 10), storagePolicy: MemoryStorageEngine())
    }

    @available(*, deprecated)
    func evictUntil(maxNbItems: Int, in cache: Cache<MemoryStorageEngine<String, String>, String>) async -> Int {
        await cache.evictUntil(maxNbItems: maxNbItems)
    }

    @available(*, deprecated)
    func isCacheable(_: (some Sendable).Type) -> Bool {
        func requiresCacheable(_: (some CacheableDataType).Type) -> Bool {
            true
        }
        return requiresCacheable(String.self)
    }
}

struct DeprecatedCacheAPITests {
    private let deprecated: any DeprecatedCacheAPI = DeprecatedCacheAPICalls()

    @Test func storagePolicyInitializerForwardsToStorageEngine() async {
        let cache = deprecated.makeCache()
        await cache.add("value", for: "key")
        #expect(await cache["key"] == "value")
    }

    @Test func evictUntilMaxNbItemsForwardsToMaxCount() async {
        let clock = ManualClock()
        let cache = Cache(policy: .fifo(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        await cache.add("old", for: "old")
        clock.advance(by: 1)
        await cache.add("new", for: "new")

        #expect(await deprecated.evictUntil(maxNbItems: 1, in: cache) == 1)
        #expect(await cache.keys() == ["new"])
    }

    @Test func cacheableDataTypeIsSendable() {
        #expect(deprecated.isCacheable(String.self))
    }
}
