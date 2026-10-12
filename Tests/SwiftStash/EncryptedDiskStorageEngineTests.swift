import Foundation
@testable import SwiftStash
import Testing

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

struct EncryptedDiskStorageEngineTests {

    private let directories = TestDirectories()
    private let encryptionKey = SymmetricKey(size: .bits256)

    private func engine(
        _ name: String,
        encryptionKey: SymmetricKey? = nil,
        options: Data.WritingOptions = [.atomic]
    ) -> DiskStorageEngine<String, String, TextDiskStorageSerializer> {
        DiskStorageEngine(
            directory: name,
            serializer: TextDiskStorageSerializer(),
            options: options,
            encryptionKey: encryptionKey ?? self.encryptionKey
        )
    }

    private func directory(_ name: String) -> URL {
        URL.swiftStashCacheDirectory.appendingPathComponent(name)
    }

    /// The entry files in a directory, by filename.
    private func entryFiles(in name: String) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory(name), includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: urls.map { try ($0.lastPathComponent, Data(contentsOf: $0)) })
    }

    // MARK: - Round Trips

    @Test func persistAndLoadEntries() {
        let name = directories.make("TestEncryptedRoundTrip")
        let date = Date(timeIntervalSince1970: 1000)
        #expect(engine(name).persist(CacheEntry(key: "a", value: "one", creation: date, lastAccess: date, accessCount: 3)))
        #expect(engine(name).persist(CacheEntry(key: "b", value: "two")))

        let entries = engine(name).load().sorted { $0.key < $1.key }

        #expect(entries.map(\.key) == ["a", "b"])
        #expect(entries.map(\.value) == ["one", "two"])
        #expect(entries.first?.creation == date)
        #expect(entries.first?.accessCount == 3)
    }

    @Test func loadMetadataAndValues() throws {
        let name = directories.make("TestEncryptedLazyLoading")
        let date = Date(timeIntervalSince1970: 1000)
        let expiration = Date(timeIntervalSince1970: 2000)
        #expect(engine(name).persist(CacheEntry(
            key: "key", value: "value", creation: date, lastAccess: date, accessCount: 2, expiration: expiration, cost: 5
        )))

        let reopened = engine(name)
        let metadata = try #require(reopened.loadMetadata()?.first)

        #expect(metadata.key == "key")
        #expect(metadata.creation == date)
        #expect(metadata.lastAccess == date)
        #expect(metadata.accessCount == 2)
        #expect(metadata.expiration == expiration)
        #expect(metadata.cost == 5)
        #expect(reopened.loadValue(for: "key") == "value")
        #expect(reopened.loadValue(for: "missing") == nil)
    }

    @Test func persistMetadataUpdatesTheEntry() throws {
        let name = directories.make("TestEncryptedPersistMetadata")
        let date = Date(timeIntervalSince1970: 1000)
        let entry = CacheEntry(key: "key", value: "value", creation: date, lastAccess: date)
        #expect(engine(name).persist(entry))
        var metadata = entry.metadata
        metadata.updateLastAccess(at: date.addingTimeInterval(5))

        #expect(engine(name).persistMetadata(metadata))

        let reloaded = try #require(engine(name).load().first)
        #expect(reloaded.lastAccess == date.addingTimeInterval(5))
        #expect(reloaded.accessCount == 1)
        #expect(reloaded.value == "value")
    }

    @Test func deleteRemovesEntries() throws {
        let name = directories.make("TestEncryptedDelete")
        let engine = engine(name)
        let entry = CacheEntry(key: "a", value: "one")
        #expect(engine.persist(entry))
        #expect(engine.persist(CacheEntry(key: "b", value: "two")))
        #expect(engine.persist(CacheEntry(key: "c", value: "three")))

        engine.delete(entry)
        engine.delete(forKey: "b")

        #expect(self.engine(name).load().map(\.key) == ["c"])
        #expect(try entryFiles(in: name).count == 1)
    }

    @Test func deleteBeforeLoadingRemovesTheEntry() {
        let name = directories.make("TestEncryptedDeleteBeforeLoading")
        #expect(engine(name).persist(CacheEntry(key: "key", value: "value")))

        engine(name).delete(forKey: "key")

        #expect(engine(name).load().isEmpty)
    }

    @Test func clearRemovesAllEntries() throws {
        let name = directories.make("TestEncryptedClear")
        let engine = engine(name)
        #expect(engine.persist(CacheEntry(key: "a", value: "one")))
        #expect(engine.persist(CacheEntry(key: "b", value: "two")))

        engine.clear()

        #expect(self.engine(name).load().isEmpty)
        #expect(try entryFiles(in: name).isEmpty)
    }

    @Test func withoutOverwritingPreservesExistingValue() {
        let name = directories.make("TestEncryptedWithoutOverwriting")
        let engine = engine(name, options: [.withoutOverwriting])

        #expect(engine.persist(CacheEntry(key: "key", value: "old")))
        #expect(!engine.persist(CacheEntry(key: "key", value: "new")))
        #expect(engine.load().first?.value == "old")
    }

    @Test func equivalentUnicodeKeysShareOneFile() throws {
        let name = directories.make("TestEncryptedUnicode")
        let engine = engine(name)

        #expect(engine.persist(CacheEntry(key: "\u{E9}", value: "old")))
        #expect(engine.persist(CacheEntry(key: "e\u{301}", value: "new")))

        #expect(try entryFiles(in: name).count == 1)
        #expect(self.engine(name).load().map(\.value) == ["new"])
        engine.delete(forKey: "\u{E9}")
        #expect(self.engine(name).load().isEmpty)
    }

    @Test func otherInitializersAcceptAnEncryptionKey() throws {
        enum Key: String, CacheKey {
            case known
        }
        let name = directories.make("TestEncryptedInitializers")
        let stringEngine = DiskStorageEngine(directory: name, serializer: TextDiskStorageSerializer(), encryptionKey: encryptionKey)
        let typedEngine = DiskStorageEngine(directory: name, keyType: Key.self, serializer: TextDiskStorageSerializer(), encryptionKey: encryptionKey)

        #expect(stringEngine.persist(CacheEntry(key: "known", value: "value")))

        #expect(typedEngine.load().first?.value == "value")
        #expect(try entryFiles(in: name).values.allSatisfy { $0.starts(with: Data("SSC1".utf8)) })
    }

    // MARK: - Serializers

    private struct Account: Codable, Equatable {
        let number: String
        let balance: Int
    }

    @Test func encryptionWorksWithAJSONSerializer() throws {
        let name = directories.make("TestEncryptedJSON")
        let account = Account(number: "FR7630006000011234567890189", balance: 4200)
        let engine = DiskStorageEngine(directory: name, serializer: JsonDiskStorageSerializer<Account>(), encryptionKey: encryptionKey)

        #expect(engine.persist(CacheEntry(key: "account", value: account)))

        let reopened = DiskStorageEngine(directory: name, serializer: JsonDiskStorageSerializer<Account>(), encryptionKey: encryptionKey)
        #expect(reopened.load().first?.value == account)
        let contents = try #require(entryFiles(in: name).values.first)
        #expect(!contents.contains(Data(account.number.utf8)))
        #expect(!contents.contains(Data("balance".utf8)))
    }

    /// Stores `Data` values unchanged.
    private struct DataSerializer: DiskStorageSerializer {
        func serialize(_ value: Data) throws -> Data {
            value
        }

        func deserialize(_ data: Data) throws -> Data? {
            data
        }
    }

    @Test func encryptionWorksWithACustomSerializer() throws {
        let name = directories.make("TestEncryptedCustomSerializer")
        let value = Data((0 ..< 30000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let engine = DiskStorageEngine(directory: name, serializer: DataSerializer(), encryptionKey: encryptionKey)

        #expect(engine.persist(CacheEntry(key: "key", value: value)))

        #expect(DiskStorageEngine(directory: name, serializer: DataSerializer(), encryptionKey: encryptionKey).load().first?.value == value)
        let contents = try #require(entryFiles(in: name).values.first)
        #expect(!contents.contains(value.prefix(64)))
    }

    // MARK: - Secrecy

    @Test func entryFilesRevealNoCacheKeyValueOrMetadata() throws {
        let name = directories.make("TestEncryptedSecrecy")
        let key = "account-FR7630006000011234567890189"
        let value = "balance: 4200 EUR"
        let date = Date(timeIntervalSince1970: 1_746_364_519)
        #expect(engine(name).persist(CacheEntry(
            key: key, value: value, creation: date, lastAccess: date, accessCount: 7, expiration: date.addingTimeInterval(60), cost: 99
        )))

        let files = try entryFiles(in: name)
        let (fileName, contents) = try #require(files.first)
        #expect(files.count == 1)
        #expect(contents.starts(with: Data("SSC1".utf8)))
        let plainName = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".cache_entry"
        #expect(fileName != plainName)
        #expect(fileName.hasSuffix(".cache_entry"))
        #expect(fileName.count == plainName.count)
        #expect(!fileName.contains("account"))
        let plaintexts = [key, "FR7630006000011234567890189", value, "1746364519", "accessCount", "creation", "lastAccess", "expiration", "cost"]
        for plaintext in plaintexts {
            #expect(!contents.contains(Data(plaintext.utf8)), "\(plaintext) appears in the entry file")
            #expect(!fileName.contains(plaintext))
        }
    }

    @Test func entryFilesDependOnTheEncryptionKey() throws {
        let first = directories.make("TestEncryptedFirstEncryptionKey")
        let second = directories.make("TestEncryptedSecondEncryptionKey")
        let entry = CacheEntry(key: "key", value: "value", creation: Date(timeIntervalSince1970: 1000), lastAccess: Date(timeIntervalSince1970: 1000))

        #expect(engine(first).persist(entry))
        #expect(engine(second, encryptionKey: SymmetricKey(size: .bits256)).persist(entry))

        #expect(try entryFiles(in: first).keys != entryFiles(in: second).keys)
    }

    @Test func persistingTheSameEntryTwiceProducesDifferentCiphertext() throws {
        let name = directories.make("TestEncryptedNonces")
        let entry = CacheEntry(key: "key", value: "value", creation: Date(timeIntervalSince1970: 1000), lastAccess: Date(timeIntervalSince1970: 1000))

        #expect(engine(name).persist(entry))
        let first = try #require(entryFiles(in: name).values.first)
        #expect(engine(name).persist(entry))
        let second = try #require(entryFiles(in: name).values.first)

        #expect(first.count == second.count)
        #expect(first != second)
    }

    @Test func cacheKeyLengthWithinABucketIsHidden() throws {
        let short = directories.make("TestEncryptedShortKey")
        let long = directories.make("TestEncryptedLongKey")
        let date = Date(timeIntervalSince1970: 1000)

        #expect(engine(short).persist(CacheEntry(key: "a", value: "value", creation: date, lastAccess: date)))
        #expect(engine(long).persist(CacheEntry(key: String(repeating: "k", count: 60), value: "value", creation: date, lastAccess: date)))

        let shortFile = try #require(entryFiles(in: short).values.first)
        let longFile = try #require(entryFiles(in: long).values.first)
        #expect(shortFile.count == longFile.count)
    }

    @Test func longCacheKeysPersistAndLoad() {
        let name = directories.make("TestEncryptedLongKeys")
        let key = String(repeating: "k", count: 1000)

        #expect(engine(name).persist(CacheEntry(key: key, value: "value")))

        #expect(engine(name).load().map(\.key) == [key])
    }

    // MARK: - Unreadable Entry Files

    /// A sealed region of an encrypted entry file.
    enum SealedRegion: CaseIterable {
        case header
        case value
    }

    /// An encrypted entry file's sealed entry header and sealed value, located by the header
    /// region's length that follows the 4-byte signature.
    private func sealedRegions(of data: Data) -> (header: Data, value: Data) {
        let headerLength = data[4 ..< 8].reduce(0) { $0 << 8 | Int($1) }
        return (Data(data[8 ..< 8 + headerLength]), Data(data[(8 + headerLength)...]))
    }

    /// An encrypted entry file made of a header region and a value region.
    private func encryptedFile(header: Data, value: Data) -> Data {
        var data = Data("SSC1".utf8)
        withUnsafeBytes(of: UInt32(header.count).bigEndian) { data.append(contentsOf: $0) }
        return data + header + value
    }

    /// Persists entries and returns their entry file locations, by cache key.
    private func persist(_ entries: [String: String], in name: String) throws -> [String: URL] {
        let engine = engine(name)
        var urls: [String: URL] = [:]
        for (key, value) in entries {
            let before = try Set(entryFiles(in: name).keys)
            #expect(engine.persist(CacheEntry(key: key, value: value)))
            let added = try Set(entryFiles(in: name).keys).subtracting(before)
            urls[key] = try directory(name).appendingPathComponent(#require(added.first))
        }
        return urls
    }

    @Test(arguments: SealedRegion.allCases) func tamperedEntryFilesAreDeleted(region: SealedRegion) throws {
        let name = directories.make("TestEncryptedTampered")
        let urls = try persist(["a": "one", "b": "two"], in: name)
        let url = try #require(urls["a"])
        var data = try Data(contentsOf: url)
        // Flip a bit of the header ciphertext, past the 8-byte prefix and 12-byte nonce, or of the value tag.
        data[region == .header ? 8 + 12 + 8 : data.count - 1] ^= 0x01
        try data.write(to: url)

        #expect(engine(name).load().map(\.key) == ["b"])
        #expect(try entryFiles(in: name).keys.sorted() == [try #require(urls["b"]).lastPathComponent])
    }

    @Test func tamperedSealedValuesAreNeverReturnedByLazyLoading() throws {
        let name = directories.make("TestEncryptedTamperedValue")
        let url = try #require(persist(["a": "one"], in: name)["a"])
        var data = try Data(contentsOf: url)
        data[data.count - 1] ^= 0x01
        try data.write(to: url)
        let engine = engine(name)

        #expect(engine.loadMetadata()?.map(\.key) == ["a"])
        #expect(engine.loadValue(for: "a") == nil)
        #expect(try entryFiles(in: name).isEmpty)
    }

    @Test func truncatedEncryptedEntryFilesAreDeleted() throws {
        let name = directories.make("TestEncryptedTruncated")
        let url = try #require(persist(["a": "one"], in: name)["a"])
        try Data(Data(contentsOf: url).prefix(40)).write(to: url)

        #expect(engine(name).load().isEmpty)
        #expect(try entryFiles(in: name).isEmpty)
    }

    @Test(arguments: SealedRegion.allCases) func sealedRegionsMovedBetweenEntryFilesAreRejected(region: SealedRegion) throws {
        let name = directories.make("TestEncryptedSwapped")
        let urls = try persist(["a": "one", "b": "two"], in: name)
        let a = try #require(urls["a"])
        let b = try #require(urls["b"])
        let regionsA = try sealedRegions(of: Data(contentsOf: a))
        let regionsB = try sealedRegions(of: Data(contentsOf: b))
        // Leave only the mixed file, so nothing else can explain an empty result.
        try FileManager.default.removeItem(at: b)
        let mixed = region == .header
            ? encryptedFile(header: regionsB.header, value: regionsA.value)
            : encryptedFile(header: regionsA.header, value: regionsB.value)
        try mixed.write(to: a)

        #expect(engine(name).load().isEmpty)
        #expect(try entryFiles(in: name).isEmpty)
    }

    @Test func sealedRegionsSwappedBetweenRolesAreRejected() throws {
        let name = directories.make("TestEncryptedSwappedRoles")
        // A value that is also a valid entry header, so only role binding can reject the swap.
        let url = try #require(persist(["a": #"{"accessCount":0,"creation":1000,"key":"a","lastAccess":1000}"#], in: name)["a"])
        let regions = try sealedRegions(of: Data(contentsOf: url))
        try encryptedFile(header: regions.value, value: regions.header).write(to: url)

        #expect(engine(name).load().isEmpty)
        #expect(try entryFiles(in: name).isEmpty)
    }

    @Test func entryFilesSealedWithAnotherEncryptionKeyAreDeletedOnScan() throws {
        let name = directories.make("TestEncryptedOtherEncryptionKey")
        let previous = SymmetricKey(size: .bits256)
        #expect(engine(name, encryptionKey: previous).persist(CacheEntry(key: "old", value: "value")))
        #expect(engine(name).persist(CacheEntry(key: "new", value: "value")))

        #expect(engine(name).loadMetadata()?.map(\.key) == ["new"])
        #expect(try entryFiles(in: name).count == 1)
        #expect(engine(name, encryptionKey: previous).load().isEmpty)
    }

    @Test func plaintextEntryFilesAreDeletedRatherThanMigrated() throws {
        let name = directories.make("TestEncryptedPlaintext")
        let control = directories.make("TestEncryptedPlaintextControl")
        let legacy = Data(#"{"key":"legacy","creation":1000,"lastAccess":1001,"value":"dmFsdWU="}"#.utf8)
        for directoryName in [name, control] {
            #expect(DiskStorageEngine(directory: directoryName, serializer: TextDiskStorageSerializer()).persist(CacheEntry(key: "key", value: "value")))
            try legacy.write(to: directory(directoryName).appendingPathComponent("legacy.cache_entry"))
        }
        try Data("notes".utf8).write(to: directory(name).appendingPathComponent("notes.txt"))

        #expect(engine(name).load().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory(name).path) == ["notes.txt"])
        // The same files are readable without an encryption key.
        let plaintextEntries = DiskStorageEngine(directory: control, serializer: TextDiskStorageSerializer()).load()
        #expect(plaintextEntries.map(\.key).sorted() == ["key", "legacy"])
    }

    @Test func enginesWithoutAnEncryptionKeyDeleteEncryptedEntryFiles() throws {
        let name = directories.make("TestEncryptedWithoutEncryptionKey")
        #expect(engine(name).persist(CacheEntry(key: "key", value: "value")))

        #expect(DiskStorageEngine(directory: name, serializer: TextDiskStorageSerializer()).load().isEmpty)
        #expect(try entryFiles(in: name).isEmpty)
    }

    // MARK: - Encryption Key Strength

    #if compiler(>=6.2) && (os(macOS) || os(Linux))
        @Test func encryptionKeysShorterThan256BitsStopTheProcess() async {
            await #expect(processExitsWith: .failure) {
                _ = DiskStorageEngine(
                    directory: "TestShortEncryptionKey",
                    serializer: TextDiskStorageSerializer(),
                    encryptionKey: SymmetricKey(size: .bits128)
                )
            }
        }
    #endif
}
