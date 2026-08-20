import Foundation
@testable import SwiftStash
import Testing

@Suite(.serialized) struct MemoryStorageEngineTests {

    @Test func loadReturnsEmptyArray() {
        let engine = MemoryStorageEngine<String, String>()
        let entries = engine.load()
        #expect(entries.isEmpty)
    }

    @Test func persistReturnsTrue() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let engine = MemoryStorageEngine<String, String>()
        let entry = CacheEntry(key: "key", value: "value")
        let result = engine.persist(entry)
        #expect(result == true)
    }

    @Test func deleteDoesNotThrow() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let engine = MemoryStorageEngine<String, String>()
        let entry = CacheEntry(key: "key", value: "value")
        engine.delete(entry)
        // Should complete without error
    }

    @Test func clearDoesNotThrow() {
        let engine = MemoryStorageEngine<String, String>()
        engine.clear()
        // Should complete without error
    }
}
