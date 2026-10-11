import Foundation
import SwiftStash
import Testing

struct CacheClockTests {

    @Test func manualClockStartsAtItsInitialDate() {
        let start = Date(timeIntervalSince1970: 1000)
        #expect(ManualClock(now: start).now == start)
    }

    @Test func manualClockAdvancesAndSets() {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1000))

        clock.advance(by: 30)
        #expect(clock.now == Date(timeIntervalSince1970: 1030))

        clock.advance(by: -10)
        #expect(clock.now == Date(timeIntervalSince1970: 1020))

        clock.set(Date(timeIntervalSince1970: 5))
        #expect(clock.now == Date(timeIntervalSince1970: 5))
    }

    @Test func manualClockDoesNotMoveOnItsOwn() async throws {
        let clock = ManualClock()
        let before = clock.now
        try await Task.sleep(for: .milliseconds(10))
        #expect(clock.now == before)
    }

    @Test func networkTimeClockFollowsRealTime() async throws {
        let before = NetworkTimeClock.shared.now
        try await Task.sleep(for: .milliseconds(10))
        #expect(NetworkTimeClock.shared.now > before)
    }

    @Test func cacheTimestampsEntriesWithItsClock() async {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1000))
        let cache = Cache(storageEngine: MemoryStorageEngine<String, String>(), clock: clock)

        let added = await cache.add("value", for: "key")
        #expect(added.creation == Date(timeIntervalSince1970: 1000))

        clock.advance(by: 5)
        let read = await cache.entry(for: "key")
        #expect(read?.creation == Date(timeIntervalSince1970: 1000))
        #expect(read?.lastAccess == Date(timeIntervalSince1970: 1005))
    }

    @Test func cachesWithSeparateClocksExpireIndependently() async {
        let fastClock = ManualClock()
        let slowClock = ManualClock()
        let fast = Cache(policy: .fifo(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: fastClock)
        let slow = Cache(policy: .fifo(threshold: 10), storageEngine: MemoryStorageEngine<String, String>(), clock: slowClock)
        await fast.add("value", for: "key")
        await slow.add("value", for: "key")

        fastClock.advance(by: 10)
        await fast.evictExpired()
        await slow.evictExpired()

        #expect(await fast.isEmpty)
        #expect(await slow.count == 1)
    }
}
