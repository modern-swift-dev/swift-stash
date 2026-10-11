import Foundation
@testable import SwiftStash
import Testing

struct MemoryStorageEngineTests {

    @Test func loadReturnsEmptyArray() {
        let engine = MemoryStorageEngine<String, String>()
        let entries = engine.load()
        #expect(entries.isEmpty)
    }

    @Test func persistReturnsTrue() {
        let engine = MemoryStorageEngine<String, String>()
        let entry = CacheEntry(key: "key", value: "value")
        let result = engine.persist(entry)
        #expect(result == true)
    }

    @Test func deleteDoesNotThrow() {
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
