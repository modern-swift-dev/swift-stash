import Foundation
@testable import SwiftStash
import Testing

struct CacheEntryTests {

    @Test func initWithKeyAndValue() {
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

    @Test func optionalPayloadRetainsItsDeclaredType() {
        let empty = CacheEntry<String, String?>(key: "empty", value: nil)
        let populated = CacheEntry<String, String?>(key: "populated", value: "value")
        #expect(empty.value == nil)
        #expect(populated.value == "value")
    }

    @Test func updateLastAccessIncrementsCount() {
        var entry = CacheEntry(key: "testKey", value: "testValue")

        #expect(entry.accessCount == 0)

        entry.updateLastAccess(at: entry.creation.addingTimeInterval(1))
        #expect(entry.accessCount == 1)

        entry.updateLastAccess(at: entry.creation.addingTimeInterval(2))
        #expect(entry.accessCount == 2)
    }

    @Test func updateLastAccessUpdatesDate() {
        var entry = CacheEntry(key: "testKey", value: "testValue")
        let accessDate = entry.lastAccess.addingTimeInterval(10)

        entry.updateLastAccess(at: accessDate)

        #expect(entry.lastAccess == accessDate)
        #expect(entry.creation < accessDate)
    }

    @Test func initWithKeyAndValueUsesOneDateForCreationAndLastAccess() {
        let entry = CacheEntry(key: "testKey", value: "testValue")

        #expect(entry.creation == entry.lastAccess)
    }
}
