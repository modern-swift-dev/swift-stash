import Foundation
@testable import SwiftStash
import Testing

extension Cache {
    /// Whether the caller runs on the cache's own queue.
    func isRunningOnItsQueue() -> Bool {
        executor.isCurrent
    }
}

/// Lets a storage engine check, after the cache is created, whether it runs on the cache's queue.
private final class ExecutorProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var executor: CacheExecutor?
    private var checks: [Bool] = []
    private var loads = 0

    func attach(_ executor: CacheExecutor) {
        lock.withLock { self.executor = executor }
    }

    func record() {
        lock.withLock { checks.append(executor?.isCurrent ?? false) }
    }

    func recordLoad() {
        lock.withLock { loads += 1 }
    }

    var recordedChecks: [Bool] {
        lock.withLock { checks }
    }

    var loadCount: Int {
        lock.withLock { loads }
    }
}

/// A storage engine that counts loads and records the queue of each call.
private final class ProbingStorageEngine: StorageEngine {
    let probe: ExecutorProbe

    init(probe: ExecutorProbe) {
        self.probe = probe
    }

    func load() -> [CacheEntry<String, String>] {
        probe.recordLoad()
        probe.record()
        let date = Date(timeIntervalSince1970: 1000)
        return [CacheEntry(key: "stored", value: "value", creation: date, lastAccess: date)]
    }

    func delete(_: CacheEntry<String, String>) {
        probe.record()
    }

    func persist(_: CacheEntry<String, String>) -> Bool {
        probe.record()
        return true
    }

    func clear() {
        probe.record()
    }
}

struct CacheExecutorTests {
    private let clock = ManualClock(now: Date(timeIntervalSince1970: 1000))

    @Test func cacheWorkRunsOnItsOwnQueue() async {
        let cache = Cache(storageEngine: MemoryStorageEngine<String, String>(), clock: clock)

        #expect(await cache.isRunningOnItsQueue())
        #expect(!cache.executor.isCurrent)
    }

    @Test func eachCacheHasItsOwnQueue() async {
        let first = Cache(storageEngine: MemoryStorageEngine<String, String>(), clock: clock)
        let second = Cache(storageEngine: MemoryStorageEngine<String, String>(), clock: clock)

        #expect(first.executor !== second.executor)
    }

    @Test func storageEngineCallsRunOnTheCacheQueue() async {
        let probe = ExecutorProbe()
        let cache = Cache(policy: .fifo(threshold: 300), storageEngine: ProbingStorageEngine(probe: probe), clock: clock)
        probe.attach(cache.executor)

        await cache.add("value", for: "key")
        await cache.remove("key")
        await cache.clear()

        #expect(probe.recordedChecks == [true, true, true, true])
    }

    @Test func creatingACacheDefersLoadingToFirstUse() async {
        let probe = ExecutorProbe()
        let cache = Cache(storageEngine: ProbingStorageEngine(probe: probe), clock: clock)
        #expect(probe.loadCount == 0)

        #expect(await cache.count == 1)
        #expect(await cache["stored"] == "value")
        #expect(await cache.keys() == ["stored"])
        #expect(probe.loadCount == 1)
    }

    @Test func concurrentCallsAreSerialized() async {
        let cache = Cache(storageEngine: MemoryStorageEngine<String, Int>(), clock: clock)

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 200 {
                group.addTask {
                    await cache.add(index, for: "\(index)")
                    _ = await cache["\(index)"]
                }
            }
        }

        #expect(await cache.count == 200)
        #expect(Set(await cache.values()) == Set(0 ..< 200))
    }
}
