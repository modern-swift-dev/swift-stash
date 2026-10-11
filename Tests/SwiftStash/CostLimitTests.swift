import Foundation
@testable import SwiftStash
import Testing

struct CostLimitTests {
    private let clock = ManualClock(now: Date(timeIntervalSince1970: 1_746_364_519))
    private let directories = TestDirectories()

    /// A limit of 10 where each string costs its character count.
    private let lengthLimit = CostLimit<String>(maxCost: 10) { $0.count }

    private func makeCache(policy: EvictionPolicy = .fifo(threshold: 300)) -> Cache<MemoryStorageEngine<String, String>> {
        Cache(policy: policy, storageEngine: MemoryStorageEngine(), clock: clock, costLimit: lengthLimit)
    }

    @Test func addEvictsInPolicyOrderUntilWithinTheLimit() async {
        let cache = makeCache()
        for key in ["a", "b", "c"] {
            await cache.add(String(repeating: key, count: 4), for: key)
            clock.advance(by: 1)
        }

        #expect(await cache.keys().sorted() == ["b", "c"])
        #expect(await cache.totalCost == 8)
    }

    @Test func lruEvictsTheLeastRecentlyReadEntry() async {
        let cache = makeCache(policy: .lru(threshold: 300))
        await cache.add("aaaa", for: "a")
        clock.advance(by: 1)
        await cache.add("bbbb", for: "b")
        clock.advance(by: 1)
        _ = await cache["a"]
        clock.advance(by: 1)

        await cache.add("cccc", for: "c")

        #expect(await cache.keys().sorted() == ["a", "c"])
    }

    @Test func batchAddEnforcesTheLimit() async {
        let cache = makeCache()
        await cache.add(["d", "b", "a", "c"].map { ($0, String(repeating: $0, count: 3)) })

        #expect(await cache.keys().sorted() == ["b", "c", "d"])
        #expect(await cache.totalCost == 9)
    }

    @Test func expiredEntriesAreEvictedFirst() async {
        // By cost alone, LIFO would evict the new entry; the expired one goes first instead.
        let cache = makeCache(policy: .lifo(threshold: 10))
        await cache.add("aaaa", for: "old")
        clock.advance(by: 5)
        await cache.add("bbbb", for: "recent")
        clock.advance(by: 5)

        await cache.add("cccc", for: "new")

        #expect(await cache.keys().sorted() == ["new", "recent"])
    }

    @Test func aValueOverTheLimitIsNotKept() async {
        let cache = makeCache()
        await cache.add("small", for: "small")

        let entry = await cache.add(String(repeating: "x", count: 11), for: "huge")

        #expect(entry.cost == 11)
        #expect(await cache["huge"] == nil)
        #expect(await cache.totalCost <= 10)
    }

    @Test func replacingRemovingAndClearingUpdateTheTotal() async {
        let cache = makeCache()
        await cache.add("aaaa", for: "a")
        await cache.add("bb", for: "b")
        #expect(await cache.totalCost == 6)

        await cache.add("a", for: "a")
        #expect(await cache.totalCost == 3)

        await cache.remove("b")
        #expect(await cache.totalCost == 1)

        await cache.clear()
        #expect(await cache.totalCost == 0)
    }

    @Test func evictionUpdatesTheTotal() async {
        let cache = makeCache(policy: .fifo(threshold: 10))
        await cache.add("aaa", for: "a")
        clock.advance(by: 1)
        await cache.add("bbb", for: "b")
        await cache.evictUntil(maxCount: 1)
        #expect(await cache.totalCost == 3)

        clock.advance(by: 10)
        #expect(await cache["b"] == nil)
        #expect(await cache.totalCost == 0)
    }

    @Test func negativeCostsCountAsZero() async {
        let cache = Cache(
            storageEngine: MemoryStorageEngine<String, String>(),
            clock: clock,
            costLimit: CostLimit(maxCost: 10) { _ in -5 }
        )
        let entry = await cache.add("value", for: "key")

        #expect(entry.cost == 0)
        #expect(await cache.totalCost == 0)
    }

    @Test func withoutACostLimitCostsAreZero() async {
        let cache = Cache(storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        let entry = await cache.add(String(repeating: "x", count: 1000), for: "key")

        #expect(entry.cost == 0)
        #expect(await cache.totalCost == 0)
    }

    @Test func loadedEntriesAreCostedAndTrimmedOnTheNextAddition() async {
        let directory = directories.make("TestCostReload")
        let unlimited = Cache(
            policy: .fifo(threshold: 300),
            storageEngine: DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer()),
            clock: clock
        )
        for key in ["a", "b", "c"] {
            await unlimited.add(String(repeating: key, count: 4), for: key)
            clock.advance(by: 1)
        }

        let limited = Cache(
            policy: .fifo(threshold: 300),
            storageEngine: DiskStorageEngine(directory: directory, serializer: TextDiskStorageSerializer()),
            clock: clock,
            costLimit: lengthLimit
        )
        #expect(await limited.totalCost == 12)

        await limited.add("d", for: "d")

        #expect(await limited.keys().sorted() == ["b", "c", "d"])
        #expect(await limited.totalCost == 9)
    }
}
