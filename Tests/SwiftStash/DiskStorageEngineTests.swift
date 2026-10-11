import Foundation
@testable import SwiftStash
import Testing

#if canImport(CryptoKit)
    import CryptoKit
#endif

struct DiskStorageEngineTests {

    private let directories = TestDirectories()

    private enum TestKey: String, CacheKey {
        case known
    }

    private func createEngineWithDirectory(_ name: String) -> DiskStorageEngine<String, String, TextDiskStorageSerializer> {
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DiskStorageEngine(
            directory: name,
            serializer: TextDiskStorageSerializer()
        )
    }

    @Test func persistAndLoadEntry() {
        let dirName = directories.make("TestPersistLoad")
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

    @Test func initCreatesMissingDirectory() {
        let dirName = directories.make("TestCreatesDirectory")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        let engine = DiskStorageEngine(directory: dirName, serializer: TextDiskStorageSerializer())

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(engine.persist(CacheEntry(key: "testKey", value: "testValue")))
        #expect(engine.load().map(\.value) == ["testValue"])
    }

    @Test func longKeysPersistAndLoad() {
        let dirName = directories.make("TestLongKeys")
        let engine = createEngineWithDirectory(dirName)
        let key = String(repeating: "k", count: 1000)

        #expect(engine.persist(CacheEntry(key: key, value: "testValue")))

        let loadedEntries = engine.load()
        #expect(loadedEntries.map(\.key) == [key])
        #expect(loadedEntries.map(\.value) == ["testValue"])

        engine.clear()
    }

    @Test func persistAndLoadPreserveAccessCount() {
        let dirName = directories.make("TestAccessCount")
        let engine = createEngineWithDirectory(dirName)
        let date = Date(timeIntervalSince1970: 1000)

        #expect(engine.persist(CacheEntry(key: "key", value: "value", creation: date, lastAccess: date, accessCount: 3)))

        #expect(createEngineWithDirectory(dirName).load().first?.accessCount == 3)
        engine.clear()
    }

    @Test func deleteRemovesEntry() {
        let dirName = directories.make("TestDelete")
        let engine = createEngineWithDirectory(dirName)

        let entry = CacheEntry(key: "testKey", value: "testValue")
        _ = engine.persist(entry)

        engine.delete(entry)

        let loadedEntries = engine.load()
        #expect(loadedEntries.isEmpty)

        engine.clear()
    }

    @Test func clearRemovesAllEntries() {
        let dirName = directories.make("TestClear")
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

    @Test func clearKeepsFilesItDoesNotOwn() throws {
        let dirName = directories.make("TestClearKeepsOtherFiles")
        let engine = createEngineWithDirectory(dirName)
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
        let otherFile = directory.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: otherFile)
        _ = engine.persist(CacheEntry(key: "key1", value: "value1"))

        engine.clear()

        #expect(engine.load().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["notes.txt"])
    }

    @Test func cacheDirectoryOwnerPrefersBundleIdentifier() {
        #expect(URL.cacheDirectoryOwner(bundleIdentifier: "com.example.app", processName: "tool") == "com.example.app")
    }

    @Test func cacheDirectoryOwnerFallsBackToProcessName() {
        #expect(URL.cacheDirectoryOwner(bundleIdentifier: nil, processName: "tool") == "tool")
    }

    @Test func loadHandlesCorruptedFiles() throws {
        let dirName = directories.make("TestLoadCorrupted")
        let engine = createEngineWithDirectory(dirName)

        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
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
        let dirName = directories.make("TestLoadEmpty")
        let engine = createEngineWithDirectory(dirName)

        // Fresh directory should have no entries
        let loadedEntries = engine.load()
        #expect(loadedEntries.isEmpty)
    }

    @Test func persistMultipleEntriesAndLoad() {
        let dirName = directories.make("TestPersistMultiple")
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
        let dirName = directories.make("TestEnumKey")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = DiskStorageEngine(
            directory: dirName,
            keyType: TestKey.self,
            serializer: TextDiskStorageSerializer()
        )

        #expect(engine.persist(CacheEntry(key: .known, value: "value")))

        let entries = engine.load()
        #expect(entries.count == 1)
        #expect(entries.first?.key == .known)
        #expect(entries.first?.value == "value")

        engine.clear()
    }

    @Test func stringAndEnumKeysUseTheSameDiskRepresentation() {
        let dirName = directories.make("TestCompatibleKey")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stringEngine = DiskStorageEngine<String, String, TextDiskStorageSerializer>(
            directory: dirName,
            serializer: TextDiskStorageSerializer()
        )
        let enumEngine = DiskStorageEngine<TestKey, String, TextDiskStorageSerializer>(
            directory: dirName,
            keyType: TestKey.self,
            serializer: TextDiskStorageSerializer()
        )

        #expect(stringEngine.persist(CacheEntry(key: "known", value: "string")))
        #expect(enumEngine.persist(CacheEntry(key: .known, value: "enum")))

        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        #expect(files.filter { $0.pathExtension == "cache_entry" }.count == 1)
        #expect(enumEngine.load().first?.value == "enum")

        enumEngine.clear()
    }

    @Test func loadRemovesEntryWithUnknownEnumKey() {
        let dirName = directories.make("TestUnknownEnumKey")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(dirName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stringEngine = DiskStorageEngine<String, String, TextDiskStorageSerializer>(
            directory: dirName,
            serializer: TextDiskStorageSerializer()
        )
        let enumEngine = DiskStorageEngine<TestKey, String, TextDiskStorageSerializer>(
            directory: dirName,
            keyType: TestKey.self,
            serializer: TextDiskStorageSerializer()
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

    private func writeLegacyEntry(
        key: String,
        value: String,
        creation: Double,
        lastAccess: Double,
        directory: URL,
        fileName: String? = nil
    ) throws {
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
        try encoder.encode(entry).write(to: directory.appendingPathComponent(fileName ?? filename + ".cache_entry"))
    }

    @Test func equivalentUnicodeKeysShareOneFileAndStayDeleted() throws {
        let name = directories.make("TestUnicode")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        let engine = createEngineWithDirectory(name)
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
        let name = directories.make("TestLegacyUnicode")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        let engine = createEngineWithDirectory(name)
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
        let name = directories.make("TestLegacyMutation")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        let name = directories.make("TestFailedMigration")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Occupy the canonical filename so the migration write fails.
        try writeLegacyEntry(
            key: "\u{E9}", value: "old", creation: 1000, lastAccess: 1000, directory: directory,
            fileName: "\u{E9}".cacheEntryFileName
        )
        try writeLegacyEntry(key: "e\u{301}", value: "new", creation: 1001, lastAccess: 1001, directory: directory)
        let engine = DiskStorageEngine<String, String, TextDiskStorageSerializer>(
            directory: name, serializer: TextDiskStorageSerializer(), options: [.withoutOverwriting]
        )

        let entry = try #require(engine.load().first)
        #expect(entry.value == "new")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
        engine.delete(entry)
        #expect(createEngineWithDirectory(name).load().isEmpty)
    }

    @Test func legacyISO8601TimestampsRemainReadable() throws {
        let name = directories.make("TestLegacyTimestamp")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        let engine = createEngineWithDirectory(name)
        let json = #"{"key":"key","creation":"1970-01-01T00:16:40Z","lastAccess":"1970-01-01T00:16:41Z","value":"dmFsdWU="}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("legacy.cache_entry"))

        let entry = try #require(engine.load().first)
        #expect(entry.value == "value")
        #expect(entry.creation == Date(timeIntervalSince1970: 1000))
        #expect(entry.lastAccess == Date(timeIntervalSince1970: 1001))
        #expect(entry.accessCount == 0)
        #expect(entry.expiration == nil)
    }

    @Test func fractionalTimestampsSurviveReload() async throws {
        let name = directories.make("TestFractionalTimestamp")
        let engine = createEngineWithDirectory(name)
        let creation = Date(timeIntervalSince1970: 1000.875)
        let access = Date(timeIntervalSince1970: 1000.9375)
        #expect(engine.persist(CacheEntry(key: "key", value: "value", creation: creation, lastAccess: access)))
        let loaded = try #require(engine.load().first)
        #expect(loaded.creation == creation)
        #expect(loaded.lastAccess == access)

        let clock = ManualClock(now: Date(timeIntervalSince1970: 1000.9375))
        let cache = Cache(policy: .lru(threshold: 0.5), storageEngine: engine, clock: clock)
        await cache.evictExpired()
        #expect(await cache.count == 1)
    }

    @Test func withoutOverwritingPreservesExistingValue() throws {
        let name = directories.make("TestWritingOptions")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = DiskStorageEngine<String, String, TextDiskStorageSerializer>(
            directory: name, serializer: TextDiskStorageSerializer(), options: [.withoutOverwriting]
        )
        #expect(engine.persist(CacheEntry(key: "key", value: "old")))
        #expect(!engine.persist(CacheEntry(key: "key", value: "new")))
        #expect(engine.load().first?.value == "old")
    }

    @Test func unsupportedStringEncodingReportsPersistenceFailure() throws {
        let name = directories.make("TestEncodingFailure")
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = DiskStorageEngine(directory: name, serializer: TextDiskStorageSerializer(encoding: .ascii))
        #expect(!engine.persist(CacheEntry(key: "key", value: "🌍")))
        #expect(engine.load().isEmpty)
    }
}
