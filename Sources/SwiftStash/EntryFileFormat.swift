import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// The bytes that start every entry file in the current format.
private let entryFileSignature = Data("SSE2".utf8)

/// The spaces reserved after each header so updated metadata can be written in place.
private let entryHeaderPadding = 64

/// Names entry files and encodes, decodes, and updates their contents.
///
/// Every entry file the disk storage engine reads or writes goes through this type.
struct EntryFileFormat {

    /// The JSON Encoder
    private let encoder: JSONEncoder

    /// The JSON Decoder
    private let decoder: JSONDecoder

    init() {
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

    /// The name of the entry file holding a cache key's entry.
    func fileName(for key: String) -> String {
        key.cacheEntryFileName
    }

    /// Encodes an entry file: the signature, the header region's length as a big-endian `UInt32`,
    /// the header region (the JSON header followed by spaces reserved for metadata updates),
    /// then the serialized value.
    func encode(header: EntryHeader, value: Data) throws -> Data {
        let headerData = try encoder.encode(header)
        var data = entryFileSignature
        withUnsafeBytes(of: UInt32(headerData.count + entryHeaderPadding).bigEndian) { data.append(contentsOf: $0) }
        data.append(headerData)
        data.append(Data(repeating: UInt8(ascii: " "), count: entryHeaderPadding))
        data.append(value)
        return data
    }

    /// Decodes an entry file in the current format or the JSON format of earlier releases.
    func decode(_ data: Data) throws -> EntryFile {
        guard data.starts(with: entryFileSignature) else {
            let legacy = try decoder.decode(LegacyEntry.self, from: data)
            let header = EntryHeader(
                key: legacy.key,
                creation: legacy.creation,
                lastAccess: legacy.lastAccess,
                accessCount: legacy.accessCount ?? 0,
                expiration: legacy.expiration,
                cost: nil
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

    /// Reads an entry file's header without reading its value, except for files in the
    /// JSON format of earlier releases, which are read whole.
    func readHeader(of url: URL) throws -> ScannedFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefixLength = entryFileSignature.count + MemoryLayout<UInt32>.size
        let prefix = try handle.read(upToCount: prefixLength) ?? Data()
        guard prefix.count == prefixLength, prefix.starts(with: entryFileSignature) else {
            let file = try decode(Data(contentsOf: url))
            return ScannedFile(url: url, header: file.header, isLegacyFormat: file.isLegacyFormat)
        }
        let headerLength = prefix.dropFirst(entryFileSignature.count).reduce(0) { $0 << 8 | Int($1) }
        let headerData = try handle.read(upToCount: headerLength) ?? Data()
        guard headerData.count == headerLength else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let header = try decoder.decode(EntryHeader.self, from: headerData)
        return ScannedFile(url: url, header: header, isLegacyFormat: false)
    }

    /// Writes a header over the header region of a current-format file.
    ///
    /// - Returns: `false` when the file isn't in the current format or the header doesn't fit.
    func overwriteHeader(of url: URL, with header: EntryHeader) throws -> Bool {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let prefixLength = entryFileSignature.count + MemoryLayout<UInt32>.size
        let prefix = try handle.read(upToCount: prefixLength) ?? Data()
        guard prefix.count == prefixLength, prefix.starts(with: entryFileSignature) else {
            return false
        }
        let regionLength = prefix.dropFirst(entryFileSignature.count).reduce(0) { $0 << 8 | Int($1) }
        let headerData = try encoder.encode(header)
        guard headerData.count <= regionLength else {
            return false
        }
        try handle.seek(toOffset: UInt64(prefixLength))
        try handle.write(contentsOf: headerData + Data(repeating: UInt8(ascii: " "), count: regionLength - headerData.count))
        return true
    }
}

/// An entry file's location and header
struct ScannedFile {
    let url: URL
    let header: EntryHeader
    let isLegacyFormat: Bool
}

/// The decoded contents of an entry file
struct EntryFile {
    let header: EntryHeader
    let value: Data
    let isLegacyFormat: Bool
}

/// The metadata stored at the start of an entry file
struct EntryHeader: Codable {
    var key: String
    var creation: Date
    var lastAccess: Date
    var accessCount: Int64
    var expiration: Date?

    /// Absent when the entry was stored by a cache without a cost limit
    var cost: Int?

    init(key: String, creation: Date, lastAccess: Date, accessCount: Int64, expiration: Date?, cost: Int?) {
        self.key = key
        self.creation = creation
        self.lastAccess = lastAccess
        self.accessCount = accessCount
        self.expiration = expiration
        self.cost = cost
    }

    init(metadata: CacheEntryMetadata<some CacheKey>) {
        self.init(
            key: metadata.key.stringValue,
            creation: metadata.creation,
            lastAccess: metadata.lastAccess,
            accessCount: metadata.accessCount,
            expiration: metadata.expiration,
            cost: metadata.cost
        )
    }

    func metadata<KeyType: CacheKey>(for key: KeyType) -> CacheEntryMetadata<KeyType> {
        CacheEntryMetadata(
            key: key,
            creation: creation,
            lastAccess: lastAccess,
            accessCount: accessCount,
            expiration: expiration,
            cost: cost
        )
    }
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

extension String {
    /// A fixed-length filename, so keys of any length stay within file-system name limits.
    var cacheEntryFileName: String {
        SHA256.hash(data: Data(precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }
            .joined() + ".cache_entry"
    }
}
