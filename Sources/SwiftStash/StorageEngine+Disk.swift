import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(os)
import os.log
#endif

private let diskStorageWritingOptions: Data.WritingOptions = [.atomic]

/// A file-system-backed implementation of ``StorageEngine``.
///
/// The engine serializes each entry with `Serializer` and writes it as a separate
/// file below the app cache directory. The named directory must already exist before
/// calling ``persist(_:)``; this type does not create it.
///
/// Example:
/// ```swift
/// let engine = DiskStorageEngine(
///     directory: "myCache",
///     keyType: MyKey.self,
///     serializer: JsonDiskStorageSerializer<MyType>()
/// )
/// ```
public class DiskStorageEngine<KeyType: CacheKey, StoredType: CacheableDataType, Serializer: DiskStorageSerializer>: StorageEngine where StoredType == Serializer.SerializedType {

    /// The writing options
    private let writingOptions: Data.WritingOptions

    /// The JSON Encoder
    private let encoder: JSONEncoder

    /// The JSON Decoder
    private let decoder: JSONDecoder

    /// The directory
    private let directory: URL

    /// The Serializer type
    private let serializer: Serializer

    /// Creates an engine that stores entries in a named directory below the app cache directory.
    ///
    /// The named directory is not created by this initializer.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - serializer: The serializer used to convert stored values to and from data.
    public convenience init(
        directory: String,
        serializer: Serializer
    ) where KeyType == String {
        self.init(directory: directory, serializer: serializer, options: diskStorageWritingOptions)
    }

    /// Creates an engine for a typed key that stores entries in a named cache directory.
    ///
    /// The named directory is not created by this initializer.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - keyType: The key type used by this engine.
    ///   - serializer: The serializer used to convert stored values to and from data.
    public convenience init(
        directory: String,
        keyType _: KeyType.Type,
        serializer: Serializer
    ) {
        self.init(directory: directory, serializer: serializer, options: diskStorageWritingOptions)
    }

    /// Creates an engine that stores entries in a named directory below the app cache directory.
    ///
    /// The named directory is not created by this initializer.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - serializer: The serializer used to convert stored values to and from data.
    ///   - options: Options passed to file writes.
    public init(
        directory: String,
        serializer: Serializer,
        options: Data.WritingOptions
    ) {
        self.directory = URL.swiftStashCacheDirectory.appendingPathComponent(directory)
        writingOptions = options
        self.serializer = serializer

        encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .throw

        decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.nonConformingFloatDecodingStrategy = .throw
    }

    /// Loads decodable cache-entry files from the storage directory.
    ///
    /// Files that cannot be read, decoded, or deserialized are removed on a best-effort
    /// basis. If the directory cannot be enumerated, this method returns an empty array.
    ///
    /// - Returns: Entries successfully read and deserialized from files with the
    ///   `cache_entry` extension. Their order is unspecified.
    public func load() -> [CacheEntry<KeyType, StoredType>] {
        var entries = [CacheEntry<KeyType, StoredType>]()
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for fileURL in fileURLs where fileURL.pathExtension == "cache_entry" {
            do {
                let data = try Data(contentsOf: fileURL)
                let entry = try decoder.decode(DiskEntry.self, from: data)
                if let key = KeyType(stringValue: entry.key),
                   let value = try serializer.deserialize(entry.value) {
                    let cacheEntry = CacheEntry<KeyType, StoredType>(key: key, value: value, creation: entry.creation, lastAccess: entry.lastAccess)
                    entries.append(cacheEntry)
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                log(error)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        return entries
    }

    /// Removes the file associated with an entry's key.
    ///
    /// Failures to remove the file are ignored.
    ///
    /// - Parameter entry: The entry whose key identifies the file to remove.
    public func delete(_ entry: CacheEntry<KeyType, StoredType>) {
        let url = directory.appendingPathComponent(entry.key.stringValue.cacheEntryFileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// Serializes and writes an entry to the storage directory.
    ///
    /// The entry's key, creation date, last-access date, and serialized value are written.
    /// Writes use the configured options; the default is atomic replacement.
    /// This method does not create the named storage directory.
    ///
    /// - Parameter entry: The entry to serialize and persist.
    /// - Returns: `true` if serialization, encoding, and writing succeed; otherwise, `false`.
    public func persist(_ entry: CacheEntry<KeyType, StoredType>) -> Bool {
        do {
            let stringKey = entry.key.stringValue
            let url = directory.appendingPathComponent(stringKey.cacheEntryFileName)
            let data = try serializer.serialize(entry.value)
            let diskEntry = DiskEntry(key: stringKey, creation: entry.creation, lastAccess: entry.lastAccess, value: data)
            let diskData = try encoder.encode(diskEntry)
            try diskData.write(to: url, options: writingOptions)
            return true
        } catch {
            log(error)
            return false
        }
    }

    /// Removes every immediate item in the storage directory.
    ///
    /// This method removes all directory contents, not only cache-entry files. Failures
    /// to enumerate the directory or remove individual items are ignored.
    public func clear() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Private Entry Struct that is used for storing the cache entry along with it's metadata
    private struct DiskEntry: Codable {

        /// The Key
        var key: String

        /// The Creation Date
        var creation: Date

        /// The Last accesss of the entry
        var lastAccess: Date

        /// The Data
        var value: Data
    }

}

extension URL {
    static var swiftStashCacheDirectory: URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app-cache"
        #if os(Linux)
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        let baseURL = URL.cachesDirectory
        #endif
        let url = baseURL.appendingPathComponent("\(bundleIdentifier)-cache")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func log(_ error: any Error) {
    #if canImport(os)
    os_log("%{public}@", log: .default, type: .error, String(describing: error))
    #endif
}

private extension String {
    var cacheEntryFileName: String {
        #if canImport(CryptoKit)
        SHA256.hash(data: Data(utf8))
            .map { String(format: "%02x", $0) }
            .joined() + ".cache_entry"
        #else
        Data(utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
            + ".cache_entry"
        #endif
    }
}
