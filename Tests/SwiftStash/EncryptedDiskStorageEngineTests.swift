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
