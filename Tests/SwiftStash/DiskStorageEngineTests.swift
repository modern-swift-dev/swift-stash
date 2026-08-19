import Foundation
@testable import SwiftStash
import Testing

@Suite(.serialized) struct DiskStorageEngineTests {

    init() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
    }

    private func createEngineWithDirectory(_ name: String) -> DiskStorageEngine<String, StringDiskStorageSerializer<NSString>> {
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DiskStorageEngine(
            directory: name,
            serializer: StringDiskStorageSerializer()
        )
    }

    @Test func persistAndLoadEntry() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let dirName = "TestPersistLoad_\(UUID().uuidString)"
        let engine = createEngineWithDirectory(dirName)

        let entry = CacheEntry(key: "testKey", value: "testValue")
        let persistResult = engine.persist(entry)
        #expect(persistResult == true)

        let loadedEntries = engine.load()
        #expect(loadedEntries.count == 1)
        #expect(loadedEntries.first?.key == "testKey")
        #expect(loadedEntries.first?.value == "testValue")

        engine.clear()
    }

    @Test func deleteRemovesEntry() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let dirName = "TestDelete_\(UUID().uuidString)"
        let engine = createEngineWithDirectory(dirName)

        let entry = CacheEntry(key: "testKey", value: "testValue")
        _ = engine.persist(entry)

        engine.delete(entry)

        let loadedEntries = engine.load()
        #expect(loadedEntries.isEmpty)

        engine.clear()
    }

    @Test func clearRemovesAllEntries() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let dirName = "TestClear_\(UUID().uuidString)"
        let engine = createEngineWithDirectory(dirName)

        let entry1 = CacheEntry(key: "key1", value: "value1")
        let entry2 = CacheEntry(key: "key2", value: "value2")
        _ = engine.persist(entry1)
        _ = engine.persist(entry2)

        engine.clear()

        // After clear, load should return empty
        let loadedEntries = engine.load()
        #expect(loadedEntries.isEmpty)
    }

    @Test func loadHandlesCorruptedFiles() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let dirName = "TestLoadCorrupted_\(UUID().uuidString)"
        let engine = createEngineWithDirectory(dirName)

        // Add a valid entry first
        let entry = CacheEntry(key: "validKey", value: "validValue")
        let persistResult = engine.persist(entry)
        #expect(persistResult == true)

        // Load should work and handle any issues gracefully
        let loadedEntries = engine.load()
        #expect(!loadedEntries.isEmpty)
        #expect(loadedEntries.first?.key == "validKey")

        engine.clear()
    }

    @Test func loadEmptyDirectory() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let dirName = "TestLoadEmpty_\(UUID().uuidString)"
        let engine = createEngineWithDirectory(dirName)

        // Fresh directory should have no entries
        let loadedEntries = engine.load()
        #expect(loadedEntries.isEmpty)
    }

    @Test func persistMultipleEntriesAndLoad() {
        MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        let dirName = "TestPersistMultiple_\(UUID().uuidString)"
        let engine = createEngineWithDirectory(dirName)

        let entry1 = CacheEntry(key: "key1", value: "value1")
        let entry2 = CacheEntry(key: "key2", value: "value2")
        let entry3 = CacheEntry(key: "key3", value: "value3")

        #expect(engine.persist(entry1) == true)
        #expect(engine.persist(entry2) == true)
        #expect(engine.persist(entry3) == true)

        let loadedEntries = engine.load()
        #expect(loadedEntries.count == 3)

        let keys = loadedEntries.map(\.key).sorted()
        #expect(keys == ["key1", "key2", "key3"])

        engine.clear()
    }
}
