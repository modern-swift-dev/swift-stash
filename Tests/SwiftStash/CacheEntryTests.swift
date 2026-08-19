import Foundation
@testable import SwiftStash
import Testing

@Suite(.serialized) struct CacheEntryTests {

    init() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
    }

    @Test func initWithKeyAndValue() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let entry = CacheEntry(key: "testKey", value: "testValue")

        #expect(entry.key == "testKey")
        #expect(entry.value == "testValue")
        #expect(entry.accessCount == 0)
    }

    @Test func initWithAllParameters() {
        let creationDate = Date(timeIntervalSince1970: 1000)
        let lastAccessDate = Date(timeIntervalSince1970: 2000)

        let entry = CacheEntry(
            key: "testKey",
            value: "testValue",
            creation: creationDate,
            lastAccess: lastAccessDate
        )

        #expect(entry.key == "testKey")
        #expect(entry.value == "testValue")
        #expect(entry.creation == creationDate)
        #expect(entry.lastAccess == lastAccessDate)
    }

    @Test func updateLastAccessIncrementsCount() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        var entry = CacheEntry(key: "testKey", value: "testValue")

        #expect(entry.accessCount == 0)

        MonotonicClock.shared.tick(seconds: 1)
        entry.updateLastAccess()
        #expect(entry.accessCount == 1)

        MonotonicClock.shared.tick(seconds: 1)
        entry.updateLastAccess()
        #expect(entry.accessCount == 2)
    }

    @Test func updateLastAccessUpdatesDate() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        var entry = CacheEntry(key: "testKey", value: "testValue")
        let initialAccess = entry.lastAccess

        MonotonicClock.shared.tick(seconds: 10)
        entry.updateLastAccess()

        #expect(entry.lastAccess > initialAccess)
    }
}
