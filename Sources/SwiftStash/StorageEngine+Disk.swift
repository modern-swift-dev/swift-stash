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

/// A file-system-backed implementation of ``StorageEngine``.
///
/// The engine serializes each entry with `Serializer` and writes it as a separate
/// file in a named directory below the app cache directory. Each file holds a small
/// metadata header followed by the serialized value, unencoded. The engine creates the
/// named directory when it is initialized. Apps store entries under their bundle
/// identifier; processes without one, such as command-line tools, use their process name.
///
/// Pass an encryption key to encrypt every entry file, including its cache key and entry
/// metadata, with AES-256-GCM, and to name each file with a keyed hash of its cache key.
/// SwiftStash doesn't create or store encryption keys; the app supplies its own.
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

    /// Names entry files and encodes, decodes, and updates their contents
    private let format: EntryFileFormat

    /// The directory
    private let directory: URL

    /// The Serializer type
    private let serializer: Serializer

    /// Files discovered during loading, including legacy spellings of equivalent keys.
    private var entryFiles: [KeyType: Set<URL>] = [:]

    /// The file holding each key's newest entry, which isn't the canonical file only when migrating it failed.
    private var currentFiles: [KeyType: URL] = [:]
    private var hasLoaded = false

    /// Creates an engine that stores entries in a named directory below the app cache directory.
    ///
    /// The named directory is created if it doesn't already exist.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - serializer: The serializer used to convert stored values to and from data.
    ///   - encryptionKey: An encryption key of at least 256 bits that encrypts each entry file and
    ///     makes its name unguessable, or `nil`, the default, to store entries unencrypted. The engine
    ///     deletes entry files it can't decrypt, including files written with another encryption key
    ///     or without one.
    public convenience init(
        directory: String,
        serializer: Serializer,
        encryptionKey: SymmetricKey? = nil
    ) where KeyType == String {
        self.init(directory: directory, serializer: serializer, options: diskStorageWritingOptions, encryptionKey: encryptionKey)
    }

    /// Creates an engine for a typed key that stores entries in a named cache directory.
    ///
    /// The named directory is created if it doesn't already exist.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - keyType: The key type used by this engine.
    ///   - serializer: The serializer used to convert stored values to and from data.
    ///   - encryptionKey: An encryption key of at least 256 bits that encrypts each entry file and
    ///     makes its name unguessable, or `nil`, the default, to store entries unencrypted. The engine
    ///     deletes entry files it can't decrypt, including files written with another encryption key
    ///     or without one.
    public convenience init(
        directory: String,
        keyType _: KeyType.Type,
        serializer: Serializer,
        encryptionKey: SymmetricKey? = nil
    ) {
        self.init(directory: directory, serializer: serializer, options: diskStorageWritingOptions, encryptionKey: encryptionKey)
    }

    /// Creates an engine that stores entries in a named directory below the app cache directory.
    ///
    /// The named directory is created if it doesn't already exist.
    ///
    /// - Parameters:
    ///   - directory: The name of the directory below the app cache directory.
    ///   - serializer: The serializer used to convert stored values to and from data.
    ///   - options: Options passed to file writes, including writes that migrate legacy filenames.
    ///   - encryptionKey: An encryption key of at least 256 bits that encrypts each entry file and
    ///     makes its name unguessable, or `nil`, the default, to store entries unencrypted. The engine
    ///     deletes entry files it can't decrypt, including files written with another encryption key
    ///     or without one.
    public init(
        directory: String,
        serializer: Serializer,
        options: Data.WritingOptions,
        encryptionKey: SymmetricKey? = nil
    ) {
        if let encryptionKey {
            precondition(encryptionKey.bitCount >= 256, "The encryption key must be at least 256 bits long")
        }
        self.directory = URL.swiftStashCacheDirectory.appendingPathComponent(directory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        writingOptions = options
        self.serializer = serializer
        format = EntryFileFormat(encryptionKey: encryptionKey)
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
        scan().compactMap { key, header in
            loadValue(for: key).map { CacheEntry(metadata: header.metadata(for: key), value: $0) }
        }
    }

    /// Loads the metadata of the stored entries by reading only each file's header.
    ///
    /// Files are merged and migrated as in ``load()``, but values aren't read or deserialized.
    ///
    /// - Returns: The metadata of the entries stored in files with the `cache_entry` extension.
    public func loadMetadata() -> [CacheEntryMetadata<KeyType>]? {
        scan().map { key, header in header.metadata(for: key) }
    }

    /// Reads and deserializes the value stored for a key.
    ///
    /// A file that can't be read, decoded, or deserialized is removed.
    ///
    /// - Parameter key: The key of the entry whose value to load.
    /// - Returns: The stored value, or `nil` when it's missing or can't be read.
    public func loadValue(for key: KeyType) -> StoredType? {
        if !hasLoaded {
            _ = scan()
        }
        let url = currentFiles[key] ?? entryFileURL(for: key)
        do {
            if let value = try serializer.deserialize(format.decodeFile(at: url).value) {
                return value
            }
        } catch {
            log(error)
        }
        delete(forKey: key)
        return nil
    }

    /// Removes the file associated with an entry's key.
    ///
    /// Failures to remove the file are ignored.
    ///
    /// - Parameter entry: The entry whose key identifies the file to remove.
    public func delete(_ entry: CacheEntry<KeyType, StoredType>) {
        delete(forKey: entry.key)
    }

    /// Removes the files associated with a key.
    ///
    /// Failures to remove the files are ignored.
    ///
    /// - Parameter key: The key whose files to remove.
    public func delete(forKey key: KeyType) {
        if !hasLoaded {
            _ = scan()
        }
        let url = entryFileURL(for: key)
        let files = (entryFiles.removeValue(forKey: key) ?? []).union([url])
        currentFiles.removeValue(forKey: key)
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
            _ = scan()
        }
        do {
            let url = entryFileURL(for: entry.key)
            let header = EntryHeader(metadata: entry.metadata)
            let diskData = try format.encode(header: header, value: serializer.serialize(entry.value), for: url)
            try diskData.write(to: url, options: writingOptions)
            currentFiles[entry.key] = url
            removeLegacyFiles(for: entry.key, keeping: url)
            return true
        } catch {
            log(error)
            return false
        }
    }

    /// Writes an entry's updated metadata over the header of its file, leaving the value untouched.
    ///
    /// An encrypted entry header is re-sealed with a fresh nonce. When the new header doesn't fit
    /// in the space reserved for it, the file is rewritten around its existing value bytes, or its
    /// sealed value, without serializing the value again. In-place updates aren't atomic; a file
    /// damaged by an interrupted update is removed when it's next loaded.
    ///
    /// - Parameter metadata: The updated metadata of a stored entry.
    /// - Returns: `true` when the metadata was written; `false` when the entry's file is missing or
    ///   can't be updated, or the writing options include `withoutOverwriting`.
    @discardableResult public func persistMetadata(_ metadata: CacheEntryMetadata<KeyType>) -> Bool {
        if !hasLoaded {
            _ = scan()
        }
        guard !writingOptions.contains(.withoutOverwriting) else {
            return false
        }
        let header = EntryHeader(metadata: metadata)
        let url = entryFileURL(for: metadata.key)
        let currentURL = currentFiles[metadata.key] ?? url
        do {
            if try format.overwriteHeader(of: currentURL, with: header) {
                return true
            }
            try format.encode(header: header, keepingValueOf: currentURL, for: url).write(to: url, options: writingOptions)
            currentFiles[metadata.key] = url
            removeLegacyFiles(for: metadata.key, keeping: url)
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
        currentFiles.removeAll()
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

    /// The canonical entry file of a key.
    private func entryFileURL(for key: KeyType) -> URL {
        directory.appendingPathComponent(format.fileName(for: key.stringValue))
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

    /// Reads the header of every entry file, merges equivalent keys, and migrates legacy files.
    ///
    /// - Returns: The header of each key's newest entry.
    private func scan() -> [KeyType: EntryHeader] {
        hasLoaded = true
        entryFiles.removeAll()
        currentFiles.removeAll()
        var newest: [KeyType: ScannedFile] = [:]
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for fileURL in fileURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where fileURL.pathExtension == "cache_entry" {
            do {
                let scanned = try format.readHeader(of: fileURL)
                guard let key = KeyType(stringValue: scanned.header.key) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    continue
                }
                entryFiles[key, default: []].insert(fileURL)
                if let previous = newest[key]?.header,
                   previous.creation > scanned.header.creation ||
                   (previous.creation == scanned.header.creation && previous.lastAccess >= scanned.header.lastAccess) {
                    continue
                }
                newest[key] = scanned
            } catch {
                log(error)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        var headers: [KeyType: EntryHeader] = [:]
        for (key, scanned) in newest {
            headers[key] = scanned.header
            currentFiles[key] = scanned.url
            let url = entryFileURL(for: key)
            guard entryFiles[key] != Set([url]) || scanned.isLegacyFormat else {
                continue
            }
            do {
                let file = try format.decodeFile(at: scanned.url)
                try format.encode(header: file.header, value: file.value, for: url).write(to: url, options: writingOptions)
                currentFiles[key] = url
                removeLegacyFiles(for: key, keeping: url)
            } catch {
                log(error)
            }
        }
        return headers
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
