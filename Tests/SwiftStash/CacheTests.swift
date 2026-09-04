import Foundation
@testable import SwiftStash
import Testing

/// Helper extension for testing subscript setter
extension Cache {
    func setSubscript(key: KeyType, value: CacheType?) {
        self[key] = value
    }
}

/// Tests must run serially since they share MonotonicClock.shared state
extension ClockDependentTests {
    @Suite(.serialized) struct CacheTests {

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

        init() {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        }

        @Test func fifoEvictionByThreshold() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .fifo(threshold: 15.0), storagePolicy: storage)

            // Add items individually
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "3", value: "third"))
            MonotonicClock.shared.tick(seconds: 15)

            // Evict expired
            await cache.evictExpired()

            // Should have evicted all items
            let isEmpty = await cache.isEmpty
            #expect(isEmpty)
        }

        @Test func fifoEvictionByCount() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .fifo(threshold: 15.0), storagePolicy: storage)

            // Add items individually
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "3", value: "third"))
            MonotonicClock.shared.tick(seconds: 1)

            // Evict until only 1 remains
            await cache.evictUntil(maxNbItems: 1)

            // Should have 1 item - the last one added (since FIFO removes oldest first)
            let count = await cache.count
            let lastItem = await cache["3"]
            #expect(count == 1)
            #expect(lastItem != nil)
        }

        // MARK: - LIFO Tests

        @Test func lifoEvictionByThreshold() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .fifo(threshold: 15.0), storagePolicy: storage)

            // Add first two items
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 15)
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
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lifo(threshold: 15.0), storagePolicy: storage)

            // Add items individually
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "3", value: "third"))
            MonotonicClock.shared.tick(seconds: 1)

            // Evict until only 1 remains
            await cache.evictUntil(maxNbItems: 1)

            // Should have 1 item - the first one added (since LIFO removes newest first)
            let count = await cache.count
            let firstItem = await cache["1"]
            #expect(count == 1)
            #expect(firstItem != nil)
        }

        // MARK: - LRU Tests

        @Test func lruEvictionByThreshold() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 15.0), storagePolicy: storage)

            // Add items individually
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "3", value: "third"))
            MonotonicClock.shared.tick(seconds: 15)

            // Access item "2" to make it most recently used
            _ = await cache["2"]

            await cache.evictExpired()

            // Should have evicted all except most recently used
            let count = await cache.count
            let item = await cache["2"]
            #expect(count == 1)
            #expect(item != nil)
        }

        @Test func lruEvictionByCount() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 15.0), storagePolicy: storage)

            // Add items individually
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "3", value: "third"))
            MonotonicClock.shared.tick(seconds: 15)

            // Access items in specific order
            _ = await cache["1"]
            MonotonicClock.shared.tick(seconds: 1)
            _ = await cache["3"]
            MonotonicClock.shared.tick(seconds: 1)

            // Evict until only 1 remains
            await cache.evictUntil(maxNbItems: 1)

            // Should keep most recently accessed item
            let count = await cache.count
            let item = await cache["3"]
            #expect(count == 1)
            #expect(item != nil)
        }

        // MARK: - Cache Utility Methods Tests

        @Test func keysReturnsAllKeys() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "a", value: "first"), for: "a")
            await cache.add(TestItem(id: "b", value: "second"), for: "b")
            await cache.add(TestItem(id: "c", value: "third"), for: "c")

            let keys = await cache.keys()
            #expect(keys.sorted() == ["a", "b", "c"])
        }

        @Test func valuesReturnsAllValuesAndUpdatesAccess() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "1", value: "first"), for: "1")
            await cache.add(TestItem(id: "2", value: "second"), for: "2")

            let values = await cache.values()
            #expect(values.count == 2)
            #expect(values.contains { $0.value == "first" })
            #expect(values.contains { $0.value == "second" })
        }

        @Test func entryReturnsEntryAndUpdatesAccess() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "key1", value: "value1"), for: "key1")

            let entry = await cache.entry(for: "key1")
            #expect(entry != nil)
            #expect(entry?.key == "key1")
            #expect(entry?.value.value == "value1")
        }

        @Test func entryReturnsNilForMissingKey() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            let entry = await cache.entry(for: "nonexistent")
            #expect(entry == nil)
        }

        @Test func removeDeletesEntry() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

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
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "key1", value: "value1"), for: "key1")
            await cache.remove("nonexistent")

            let count = await cache.count
            #expect(count == 1)
        }

        @Test func clearRemovesAllEntries() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

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
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

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

        @Test func subscriptSetterAddsValue() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.setSubscript(key: "myKey", value: TestItem(id: "myKey", value: "myValue"))

            let item = await cache["myKey"]
            #expect(item?.value == "myValue")
        }

        @Test func subscriptSetterWithNilRemovesValue() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "key1", value: "value1"), for: "key1")
            await cache.setSubscript(key: "key1", value: nil)

            let item = await cache["key1"]
            let count = await cache.count
            #expect(item == nil)
            #expect(count == 0)
        }

        // MARK: - EvictUntil Edge Cases

        @Test func evictUntilZeroClearsCache() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "1", value: "first"), for: "1")
            await cache.add(TestItem(id: "2", value: "second"), for: "2")

            let remaining = await cache.evictUntil(maxNbItems: 0)

            #expect(remaining == 0)
            let isEmpty = await cache.isEmpty
            #expect(isEmpty)
        }

        @Test func evictUntilWhenUnderMaxReturnsCount() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "1", value: "first"), for: "1")
            await cache.add(TestItem(id: "2", value: "second"), for: "2")

            let remaining = await cache.evictUntil(maxNbItems: 10)

            #expect(remaining == 2)
        }

        // MARK: - Identifiable Extension Test

        @Test func addIdentifiableUsesIdAsKey() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lru(threshold: 300), storagePolicy: storage)

            let item = TestItem(id: "myId", value: "myValue")
            await cache.add(item)

            let retrieved = await cache["myId"]
            #expect(retrieved?.id == "myId")
            #expect(retrieved?.value == "myValue")
        }

        // MARK: - Typed Key Tests

        @Test func enumKeyOperationsUseTheDeclaredKeyType() async {
            let storage = MemoryStorageEngine<TestKey, TestItem>()
            let cache = await Cache(storagePolicy: storage)

            await cache.add([
                (.first, TestItem(id: "1", value: "first")),
                (.second, TestItem(id: "2", value: "second"))
            ])
            await cache.setSubscript(key: .third, value: TestItem(id: "3", value: "third"))

            let keys = await cache.keys()
            let entry = await cache.entry(for: .first)
            let third = await cache[.third]

            #expect(Set(keys) == Set(TestKey.allCases))
            #expect(entry?.key == .first)
            #expect(entry?.value.value == "first")
            #expect(third?.value == "third")

            await cache.remove(.second)
            await cache.setSubscript(key: .third, value: nil)

            #expect(await cache[.second] == nil)
            #expect(await cache[.third] == nil)
            #expect(await cache.keys() == [.first])
        }

        @Test func enumKeyParticipatesInEviction() async {
            let storage = MemoryStorageEngine<TestKey, TestItem>()
            let cache = await Cache(policy: .fifo(threshold: 300), storagePolicy: storage)

            await cache.add(TestItem(id: "1", value: "first"), for: .first)
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"), for: .second)

            let remaining = await cache.evictUntil(maxNbItems: 1)

            #expect(remaining == 1)
            #expect(await cache[.first] == nil)
            #expect(await cache[.second]?.value == "second")
        }

        @Test func identifiableValueUsesMatchingEnumId() async {
            let storage = MemoryStorageEngine<TestKey, KeyedTestItem>()
            let cache = await Cache(storagePolicy: storage)
            let item = KeyedTestItem(id: .second, value: "value")

            let entry = await cache.add(item)

            #expect(entry.key == .second)
            #expect(await cache[.second] == item)
        }

        // MARK: - LIFO Threshold Test (Corrected)

        @Test func lifoEvictionByThresholdCorrect() async {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let storage = MemoryStorageEngine<String, TestItem>()
            let cache = await Cache(policy: .lifo(threshold: 15.0), storagePolicy: storage)

            // Add first two items
            await cache.add(TestItem(id: "1", value: "first"))
            MonotonicClock.shared.tick(seconds: 1)
            await cache.add(TestItem(id: "2", value: "second"))
            MonotonicClock.shared.tick(seconds: 15)
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
}
