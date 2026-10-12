import Foundation
@testable import SwiftStash
import Testing

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Whether removing a file's permissions stops this process from reading it, which isn't the case for root.
private let removingPermissionsBlocksReading: Bool = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftStashPermissionProbe-\(UUID().uuidString)")
    guard (try? Data("probe".utf8).write(to: url)) != nil else {
        return false
    }
    defer { try? FileManager.default.removeItem(at: url) }
    try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    return (try? Data(contentsOf: url)) == nil
}()

/// Entry files the engine can't open, as with protected files while the device is locked.
///
/// Removing a file's permissions stands in for data protection, which also fails opening with a
/// "no permission" error.
@Suite(.enabled(if: removingPermissionsBlocksReading, "Removing permissions doesn't stop this process from reading files"))
struct UnopenableEntryFileTests {

    private let directories = TestDirectories()
    private let encryptionKey = SymmetricKey(size: .bits256)
    private let clock = ManualClock(now: Date(timeIntervalSince1970: 1000))

    private func engine(_ name: String, encrypted: Bool = false) -> DiskStorageEngine<String, String, TextDiskStorageSerializer> {
        DiskStorageEngine(directory: name, serializer: TextDiskStorageSerializer(), encryptionKey: encrypted ? encryptionKey : nil)
    }

    /// Persists an entry and returns the entry file it added.
    private func persist(key: String, value: String, in name: String, encrypted: Bool = false) throws -> URL {
        let engine = engine(name, encrypted: encrypted)
        let directory = URL.swiftStashCacheDirectory.appendingPathComponent(name)
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(engine.persist(CacheEntry(key: key, value: value)))
        let added = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)).subtracting(before)
        return try directory.appendingPathComponent(#require(added.first))
    }

    /// Removes or restores the permissions of a file, as data protection does when the device locks or unlocks.
    private func setLocked(_ locked: Bool, file url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: locked ? 0 : 0o644], ofItemAtPath: url.path)
    }

    @Test(arguments: [false, true]) func scansKeepEntryFilesThatCannotBeOpened(encrypted: Bool) throws {
        let name = directories.make("TestUnopenableScan")
        let file = try persist(key: "a", value: "one", in: name, encrypted: encrypted)
        _ = try persist(key: "b", value: "two", in: name, encrypted: encrypted)
        try setLocked(true, file: file)

        #expect(engine(name, encrypted: encrypted).load().map(\.key) == ["b"])
        #expect(FileManager.default.fileExists(atPath: file.path))

        try setLocked(false, file: file)
        #expect(engine(name, encrypted: encrypted).load().map(\.key).sorted() == ["a", "b"])
    }

    @Test(arguments: [false, true]) func loadingAValueKeepsAnEntryFileThatCannotBeOpened(encrypted: Bool) throws {
        let name = directories.make("TestUnopenableValue")
        let file = try persist(key: "a", value: "one", in: name, encrypted: encrypted)
        let engine = engine(name, encrypted: encrypted)
        #expect(engine.loadMetadata()?.map(\.key) == ["a"])
        try setLocked(true, file: file)

        #expect(engine.loadValue(for: "a") == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))

        try setLocked(false, file: file)
        #expect(engine.loadValue(for: "a") == "one")
    }

    @Test func cachesKeepEntryFilesTheyCannotOpen() async throws {
        let name = directories.make("TestUnopenableCache")
        let file = try persist(key: "a", value: "one", in: name)
        _ = try persist(key: "b", value: "two", in: name)
        let cache = Cache(storageEngine: engine(name), clock: clock)
        #expect(await cache.count == 2)
        try setLocked(true, file: file)

        #expect(await cache["a"] == nil)
        #expect(await cache.keys() == ["b"])
        #expect(FileManager.default.fileExists(atPath: file.path))

        try setLocked(false, file: file)
        #expect(await Cache(storageEngine: engine(name), clock: clock)["a"] == "one")
    }

    @Test func olderLegacyFilesDoNotReplaceAnEntryFileThatCannotBeOpened() throws {
        let name = directories.make("TestUnopenableMigration")
        let date = Date(timeIntervalSince1970: 1000)
        let engine = engine(name)
        #expect(engine.persist(CacheEntry(key: "a", value: "new", creation: date, lastAccess: date)))
        let file = URL.swiftStashCacheDirectory.appendingPathComponent(name).appendingPathComponent("a".cacheEntryFileName)
        let legacy = #"{"key":"a","creation":500,"lastAccess":500,"value":"b2xk"}"#
        try Data(legacy.utf8).write(to: URL.swiftStashCacheDirectory.appendingPathComponent(name).appendingPathComponent("legacy.cache_entry"))
        try setLocked(true, file: file)

        _ = self.engine(name).load()

        try setLocked(false, file: file)
        #expect(self.engine(name).load().map(\.value) == ["new"])
    }

    @Test func entryFilesThatCannotBeOpenedCanStillBeRemoved() throws {
        let name = directories.make("TestUnopenableRemoval")
        let first = try persist(key: "a", value: "one", in: name)
        let second = try persist(key: "b", value: "two", in: name)
        try setLocked(true, file: first)
        try setLocked(true, file: second)
        let engine = engine(name)

        engine.delete(forKey: "a")
        #expect(!FileManager.default.fileExists(atPath: first.path))
        engine.clear()
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }
}
