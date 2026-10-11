import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

#if canImport(os)
    import os.log
#endif

private let diskStorageWritingOptions: Data.WritingOptions = [.atomic]

/// The bytes that start every entry file in the current format.
private let entryFileSignature = Data("SSE2".utf8)

/// A file-system-backed implementation of ``StorageEngine``.
///
/// The engine serializes each entry with `Serializer` and writes it as a separate
/// file in a named directory below the app cache directory. Each file holds a small
/// metadata header followed by the serialized value, unencoded. The engine creates the
/// named directory when it is initialized. Apps store entries under their bundle
/// identifier; processes without one, such as command-line tools, use their process name.
///
/// Example:
/// ```swift
/// let engine = DiskStorageEngine(
///     directory: "myCache",
///     keyType: MyKey.self,
///     serializer: JsonDiskStorageSerializer<MyType>()
/// )
/// ```
public class DiskStorageEngine<KeyType: CacheKey, StoredType: Sendable, Serializer: DiskStorageSerializer>: StorageEngine where StoredType == Serializer.SerializedType {

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

    /// Files discovered during loading, including legacy spellings of equivalent keys.
    private var entryFiles: [KeyType: Set<URL>] = [:]
    private var hasLoaded = false

    /// Creates an engine that stores entries in a named directory below the app cache directory.
    ///
    /// The named directory is created if it doesn't already exist.
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
    /// The named directory is created if it doesn't already exist.
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
    /// The named directory is created if it doesn't already exist.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - serializer: The serializer used to convert stored values to and from data.
    ///   - options: Options passed to file writes, including writes that migrate legacy filenames.
    public init(
        directory: String,
        serializer: Serializer,
        options: Data.WritingOptions
    ) {
        self.directory = URL.swiftStashCacheDirectory.appendingPathComponent(directory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        writingOptions = options
        self.serializer = serializer

        encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .throw

        decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            let string = try container.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid legacy cache timestamp")
            }
            return date
        }
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.nonConformingFloatDecodingStrategy = .throw
    }

    /// Loads decodable cache-entry files from the storage directory.
    ///
    /// Files that cannot be read, decoded, or deserialized are removed on a best-effort
    /// basis. If the directory cannot be enumerated, this method returns an empty array.
    /// Equivalent keys are merged by newest creation date, then last-access date.
    /// Legacy filenames and files in the JSON format of earlier releases are migrated when
    /// writing succeeds; failed migrations retain their source files.
    ///
    /// - Returns: Entries successfully read and deserialized from files with the
    ///   `cache_entry` extension. Their order is unspecified.
    public func load() -> [CacheEntry<KeyType, StoredType>] {
        hasLoaded = true
        var entries: [KeyType: LoadedEntry] = [:]
        entryFiles.removeAll()
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for fileURL in fileURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where fileURL.pathExtension == "cache_entry" {
            do {
                let file = try decodeFile(Data(contentsOf: fileURL))
                if let key = KeyType(stringValue: file.header.key),
                   let value = try serializer.deserialize(file.value) {
                    let cacheEntry = CacheEntry<KeyType, StoredType>(
                        key: key,
                        value: value,
                        creation: file.header.creation,
                        lastAccess: file.header.lastAccess,
                        accessCount: file.header.accessCount,
                        expiration: file.header.expiration,
                        cost: file.header.cost
                    )
                    entryFiles[key, default: []].insert(fileURL)
                    if let previous = entries[key],
                       previous.entry.creation > cacheEntry.creation ||
                       (previous.entry.creation == cacheEntry.creation && previous.entry.lastAccess >= cacheEntry.lastAccess) {
                        continue
                    }
                    entries[key] = LoadedEntry(entry: cacheEntry, file: file)
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                log(error)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        for (key, loaded) in entries {
            let url = directory.appendingPathComponent(key.stringValue.cacheEntryFileName)
            guard entryFiles[key] != Set([url]) || loaded.file.isLegacyFormat else {
                continue
            }
            do {
                let data = try encodeFile(header: loaded.file.header, value: loaded.file.value)
                try data.write(to: url, options: writingOptions)
                removeLegacyFiles(for: key, keeping: url)
            } catch {
                log(error)
            }
        }
        return entries.values.map(\.entry)
    }

    /// Removes the file associated with an entry's key.
    ///
    /// Failures to remove the file are ignored.
    ///
    /// - Parameter entry: The entry whose key identifies the file to remove.
    public func delete(_ entry: CacheEntry<KeyType, StoredType>) {
        if !hasLoaded {
            _ = load()
        }
        let url = directory.appendingPathComponent(entry.key.stringValue.cacheEntryFileName)
        let files = (entryFiles.removeValue(forKey: entry.key) ?? []).union([url])
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Serializes and writes an entry to the storage directory.
    ///
    /// The entry's key, creation date, last-access date, access count, expiration date, cost, and serialized value are written.
    /// Writes use the configured options; the default is atomic replacement.
    ///
    /// - Parameter entry: The entry to serialize and persist.
    /// - Returns: `true` if serialization, encoding, and writing succeed; otherwise, `false`.
    @discardableResult public func persist(_ entry: CacheEntry<KeyType, StoredType>) -> Bool {
        if !hasLoaded {
            _ = load()
        }
        do {
            let stringKey = entry.key.stringValue
            let url = directory.appendingPathComponent(stringKey.cacheEntryFileName)
            let header = EntryHeader(
                key: stringKey,
                creation: entry.creation,
                lastAccess: entry.lastAccess,
                accessCount: entry.accessCount,
                expiration: entry.expiration,
                cost: entry.cost
            )
            let diskData = try encodeFile(header: header, value: serializer.serialize(entry.value))
            try diskData.write(to: url, options: writingOptions)
            removeLegacyFiles(for: entry.key, keeping: url)
            return true
        } catch {
            log(error)
            return false
        }
    }

    /// Removes every cache-entry file in the storage directory.
    ///
    /// Only files with the `cache_entry` extension are removed; other directory contents
    /// are left in place. Failures to enumerate the directory or remove individual files
    /// are ignored.
    public func clear() {
        entryFiles.removeAll()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents where url.pathExtension == "cache_entry" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeLegacyFiles(for key: KeyType, keeping url: URL) {
        var remaining: Set<URL> = [url]
        for file in entryFiles[key] ?? [] where file != url {
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                remaining.insert(file)
            }
        }
        entryFiles[key] = remaining
    }

    /// Encodes an entry file: the signature, the header length as a big-endian `UInt32`,
    /// the JSON header, then the serialized value.
    private func encodeFile(header: EntryHeader, value: Data) throws -> Data {
        let headerData = try encoder.encode(header)
        var data = entryFileSignature
        withUnsafeBytes(of: UInt32(headerData.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(headerData)
        data.append(value)
        return data
    }

    /// Decodes an entry file in the current format or the JSON format of earlier releases.
    private func decodeFile(_ data: Data) throws -> EntryFile {
        guard data.starts(with: entryFileSignature) else {
            let legacy = try decoder.decode(LegacyEntry.self, from: data)
            let header = EntryHeader(
                key: legacy.key,
                creation: legacy.creation,
                lastAccess: legacy.lastAccess,
                accessCount: legacy.accessCount ?? 0,
                expiration: legacy.expiration,
                cost: 0
            )
            return EntryFile(header: header, value: legacy.value, isLegacyFormat: true)
        }
        let lengthStart = data.startIndex + entryFileSignature.count
        let headerStart = lengthStart + MemoryLayout<UInt32>.size
        guard data.endIndex >= headerStart else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let headerLength = data[lengthStart ..< headerStart].reduce(0) { $0 << 8 | Int($1) }
        let headerEnd = headerStart + headerLength
        guard data.endIndex >= headerEnd else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let header = try decoder.decode(EntryHeader.self, from: data[headerStart ..< headerEnd])
        return EntryFile(header: header, value: Data(data[headerEnd...]), isLegacyFormat: false)
    }

    private struct LoadedEntry {
        let entry: CacheEntry<KeyType, StoredType>
        let file: EntryFile
    }

    /// The decoded contents of an entry file
    private struct EntryFile {
        let header: EntryHeader
        let value: Data
        let isLegacyFormat: Bool
    }

    /// The metadata stored at the start of an entry file
    private struct EntryHeader: Codable {
        var key: String
        var creation: Date
        var lastAccess: Date
        var accessCount: Int64
        var expiration: Date?
        var cost: Int
    }

    /// An entry file in the JSON format of earlier releases, with a base64-encoded value
    private struct LegacyEntry: Decodable {
        var key: String
        var creation: Date
        var lastAccess: Date

        /// Absent from entries written before access counts were stored
        var accessCount: Int64?

        /// Absent from entries written before per-entry lifetimes
        var expiration: Date?

        var value: Data
    }

}

extension URL {
    /// The root directory for disk storage, named after the bundle identifier or,
    /// for processes without one such as command-line tools, the process name.
    static var swiftStashCacheDirectory: URL {
        let owner = cacheDirectoryOwner(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processName: ProcessInfo.processInfo.processName
        )
        #if os(Linux)
            let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        #else
            let baseURL = URL.cachesDirectory
        #endif
        let url = baseURL.appendingPathComponent("\(owner)-cache")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cacheDirectoryOwner(bundleIdentifier: String?, processName: String) -> String {
        bundleIdentifier ?? processName
    }
}

private func log(_ error: any Error) {
    #if canImport(os)
        os_log("%{public}@", log: .default, type: .error, String(describing: error))
    #endif
}

extension String {
    /// A fixed-length filename, so keys of any length stay within file-system name limits.
    var cacheEntryFileName: String {
        SHA256.hash(data: Data(precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }
            .joined() + ".cache_entry"
    }
}
