import Foundation
@testable import SwiftStash
import Testing

#if canImport(CryptoKit)
import CryptoKit
#endif

extension ClockDependentTests {
    @Suite(.serialized) struct DiskStorageEngineTests {

        private enum TestKey: String, CacheKey {
            case known
        }

        init() {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
        }

        private func createEngineWithDirectory(_ name: String) -> DiskStorageEngine<String, String, StringDiskStorageSerializer<NSString>> {
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

        @Test func loadHandlesCorruptedFiles() throws {
            MonotonicClock.shared.reset(year: 2025, month: 5, day: 4, hour: 13, minute: 15, second: 19)
            let dirName = "TestLoadCorrupted_\(UUID().uuidString)"
            let engine = createEngineWithDirectory(dirName)

            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
            defer { try? FileManager.default.removeItem(at: directory) }
            let corrupted = directory.appendingPathComponent("corrupted.cache_entry")
            try Data("not JSON".utf8).write(to: corrupted)

            // Add a valid entry alongside the corrupt file.
            let entry = CacheEntry(key: "validKey", value: "validValue")
            let persistResult = engine.persist(entry)
            #expect(persistResult == true)

            // Loading must retain the valid entry and remove the corrupt file.
            let loadedEntries = engine.load()
            #expect(loadedEntries.count == 1)
            #expect(!FileManager.default.fileExists(atPath: corrupted.path))
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

        @Test func persistAndLoadEnumKey() {
            let dirName = "TestEnumKey_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let engine = DiskStorageEngine(
                directory: dirName,
                keyType: TestKey.self,
                serializer: StringDiskStorageSerializer()
            )

            #expect(engine.persist(CacheEntry(key: .known, value: "value")))

            let entries = engine.load()
            #expect(entries.count == 1)
            #expect(entries.first?.key == .known)
            #expect(entries.first?.value == "value")

            engine.clear()
        }

        @Test func stringAndEnumKeysUseTheSameDiskRepresentation() {
            let dirName = "TestCompatibleKey_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stringEngine = DiskStorageEngine<String, String, StringDiskStorageSerializer<NSString>>(
                directory: dirName,
                serializer: StringDiskStorageSerializer()
            )
            let enumEngine = DiskStorageEngine<TestKey, String, StringDiskStorageSerializer<NSString>>(
                directory: dirName,
                keyType: TestKey.self,
                serializer: StringDiskStorageSerializer()
            )

            #expect(stringEngine.persist(CacheEntry(key: "known", value: "string")))
            #expect(enumEngine.persist(CacheEntry(key: .known, value: "enum")))

            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            #expect(files.filter { $0.pathExtension == "cache_entry" }.count == 1)
            #expect(enumEngine.load().first?.value == "enum")

            enumEngine.clear()
        }

        @Test func loadRemovesEntryWithUnknownEnumKey() {
            let dirName = "TestUnknownEnumKey_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stringEngine = DiskStorageEngine<String, String, StringDiskStorageSerializer<NSString>>(
                directory: dirName,
                serializer: StringDiskStorageSerializer()
            )
            let enumEngine = DiskStorageEngine<TestKey, String, StringDiskStorageSerializer<NSString>>(
                directory: dirName,
                keyType: TestKey.self,
                serializer: StringDiskStorageSerializer()
            )

            #expect(stringEngine.persist(CacheEntry(key: "unknown", value: "value")))
            #expect(enumEngine.load().isEmpty)

            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            #expect(files.allSatisfy { $0.pathExtension != "cache_entry" })

            enumEngine.clear()
        }

        private struct LegacyEntry: Encodable {
            let key: String
            let creation: Date
            let lastAccess: Date
            let value: Data
        }

        private func writeLegacyEntry(key: String, value: String, creation: Double, lastAccess: Double, directory: URL) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let entry = LegacyEntry(
                key: key,
                creation: Date(timeIntervalSince1970: creation),
                lastAccess: Date(timeIntervalSince1970: lastAccess),
                value: Data(value.utf8)
            )
            // Reproduce the old filename format without Unicode normalization.
            #if canImport(CryptoKit)
            let filename = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            #else
            let filename = Data(key.utf8).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "=", with: "")
            #endif
            try encoder.encode(entry).write(to: directory.appendingPathComponent(filename + ".cache_entry"))
        }

        @Test func equivalentUnicodeKeysShareOneFileAndStayDeleted() throws {
            let name = "TestUnicode_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            let engine = createEngineWithDirectory(name)
            defer { try? FileManager.default.removeItem(at: directory) }
            let composed = "\u{E9}"
            let decomposed = "e\u{301}"

            #expect(engine.persist(CacheEntry(key: composed, value: "old")))
            #expect(engine.persist(CacheEntry(key: decomposed, value: "new")))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
            #expect(engine.load().first?.value == "new")

            engine.delete(CacheEntry(key: composed, value: "new"))
            #expect(createEngineWithDirectory(name).load().isEmpty)
        }

        @Test(arguments: [false, true]) func legacyDuplicatesMigrateTheNewestEntry(useLastAccess: Bool) throws {
            let name = "TestLegacyUnicode_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            let engine = createEngineWithDirectory(name)
            defer { try? FileManager.default.removeItem(at: directory) }
            try writeLegacyEntry(key: "\u{E9}", value: "old", creation: 1000, lastAccess: 1002, directory: directory)
            try writeLegacyEntry(key: "e\u{301}", value: "new", creation: useLastAccess ? 1000 : 1001, lastAccess: 1003, directory: directory)

            let entries = engine.load()
            #expect(entries.count == 1)
            #expect(entries.first?.value == "new")
            #expect(entries.first?.creation == Date(timeIntervalSince1970: useLastAccess ? 1000 : 1001))
            #expect(entries.first?.lastAccess == Date(timeIntervalSince1970: 1003))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
            #expect(createEngineWithDirectory(name).load().first?.value == "new")

            engine.delete(try #require(entries.first))
            #expect(createEngineWithDirectory(name).load().isEmpty)
        }

        @Test(arguments: [false, true]) func legacyEntriesSupportMutationBeforeLoading(overwrite: Bool) throws {
            let name = "TestLegacyMutation_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try writeLegacyEntry(key: "e\u{301}", value: "old", creation: 1000, lastAccess: 1000, directory: directory)
            let engine = createEngineWithDirectory(name)
            let entry = CacheEntry(key: "\u{E9}", value: "new")
            if overwrite {
                #expect(engine.persist(entry))
                #expect(createEngineWithDirectory(name).load().first?.value == "new")
            }
            engine.delete(entry)
            #expect(createEngineWithDirectory(name).load().isEmpty)
        }

        @Test func failedMigrationRetainsSourcesAndDeleteRemovesAllAliases() throws {
            let name = "TestFailedMigration_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try writeLegacyEntry(key: "\u{E9}", value: "old", creation: 1000, lastAccess: 1000, directory: directory)
            try writeLegacyEntry(key: "e\u{301}", value: "new", creation: 1001, lastAccess: 1001, directory: directory)
            let engine = DiskStorageEngine<String, String, StringDiskStorageSerializer<NSString>>(
                directory: name, serializer: StringDiskStorageSerializer(), options: [.withoutOverwriting]
            )

            let entry = try #require(engine.load().first)
            #expect(entry.value == "new")
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
            engine.delete(entry)
            #expect(createEngineWithDirectory(name).load().isEmpty)
        }

        @Test func legacyISO8601TimestampsRemainReadable() throws {
            let name = "TestLegacyTimestamp_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            let engine = createEngineWithDirectory(name)
            defer { try? FileManager.default.removeItem(at: directory) }
            let json = #"{"key":"key","creation":"1970-01-01T00:16:40Z","lastAccess":"1970-01-01T00:16:41Z","value":"dmFsdWU="}"#
            try Data(json.utf8).write(to: directory.appendingPathComponent("legacy.cache_entry"))

            let entry = try #require(engine.load().first)
            #expect(entry.value == "value")
            #expect(entry.creation == Date(timeIntervalSince1970: 1000))
            #expect(entry.lastAccess == Date(timeIntervalSince1970: 1001))
        }

        @Test func fractionalTimestampsSurviveReload() async throws {
            let name = "TestFractionalTimestamp_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            let engine = createEngineWithDirectory(name)
            defer { try? FileManager.default.removeItem(at: directory) }
            let creation = Date(timeIntervalSince1970: 1000.875)
            let access = Date(timeIntervalSince1970: 1000.9375)
            #expect(engine.persist(CacheEntry(key: "key", value: "value", creation: creation, lastAccess: access)))
            let loaded = try #require(engine.load().first)
            #expect(loaded.creation == creation)
            #expect(loaded.lastAccess == access)

            MonotonicClock.shared.set(unixTimestamp: 1000.9375)
            let cache = await Cache(policy: .lru(threshold: 0.5), storagePolicy: engine)
            await cache.evictExpired()
            #expect(await cache.count == 1)
        }

        @Test func withoutOverwritingPreservesExistingValue() throws {
            let name = "TestWritingOptions_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let engine = DiskStorageEngine<String, String, StringDiskStorageSerializer<NSString>>(
                directory: name, serializer: StringDiskStorageSerializer(), options: [.withoutOverwriting]
            )
            #expect(engine.persist(CacheEntry(key: "key", value: "old")))
            #expect(!engine.persist(CacheEntry(key: "key", value: "new")))
            #expect(engine.load().first?.value == "old")
        }

        @Test func unsupportedStringEncodingReportsPersistenceFailure() throws {
            let name = "TestEncodingFailure_\(UUID().uuidString)"
            let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let engine = DiskStorageEngine(directory: name, serializer: StringDiskStorageSerializer<NSString>(encoding: .ascii))
            #expect(!engine.persist(CacheEntry(key: "key", value: "🌍")))
            #expect(engine.load().isEmpty)
        }
    }
}
