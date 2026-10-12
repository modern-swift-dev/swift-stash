import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// The bytes that start every entry file in the current format.
private let entryFileSignature = Data("SSE2".utf8)

/// The bytes that start every encrypted entry file.
let encryptedEntryFileSignature = Data("SSC1".utf8)

/// The spaces reserved after each header so updated metadata can be written in place.
private let entryHeaderPadding = 64

/// The size that sealed entry headers are padded to a multiple of, so their length doesn't reveal the cache key's.
private let entryHeaderBucketSize = 256

/// Names entry files and encodes, decodes, and updates their contents.
///
/// Every entry file the disk storage engine reads or writes goes through this type. With an
/// encryption key, entry files are encrypted (see ADR-0002) and files in any other format are
/// rejected; without one, encrypted files are rejected.
struct EntryFileFormat {

    /// The JSON Encoder
    private let encoder: JSONEncoder

    /// The JSON Decoder
    private let decoder: JSONDecoder

    /// Seals and names entry files, or `nil` to store them unencrypted
    private let cipher: EntryFileCipher?

    init(encryptionKey: SymmetricKey?) {
        cipher = encryptionKey.map(EntryFileCipher.init(encryptionKey:))
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
        cipher?.fileName(for: key) ?? key.cacheEntryFileName
    }

    /// Encodes the entry file at a location: the signature, the header region's length as a
    /// big-endian `UInt32`, the header region, then the value region.
    ///
    /// Plaintext files hold the JSON header followed by spaces reserved for metadata updates,
    /// then the serialized value. Encrypted files hold the sealed entry header, padded to a
    /// bucket, then the sealed value.
    func encode(header: EntryHeader, value: Data, for url: URL) throws -> Data {
        let headerRegion: Data
        let valueRegion: Data
        if let cipher {
            headerRegion = try sealHeader(header, with: cipher, for: url)
            valueRegion = try cipher.seal(value, as: .value, inFileNamed: url.lastPathComponent)
        } else {
            let headerData = try encoder.encode(header)
            headerRegion = padded(headerData, to: headerData.count + entryHeaderPadding)
            valueRegion = value
        }
        return assemble(headerRegion: headerRegion, valueRegion: valueRegion)
    }

    /// Encodes the entry file at a location with a new header and the value of an existing entry file.
    ///
    /// An encrypted file staying at its location keeps its sealed value as is, without opening it.
    func encode(header: EntryHeader, keepingValueOf source: URL, for url: URL) throws -> Data {
        guard let cipher, source == url else {
            return try encode(header: header, value: decodeFile(at: source).value, for: url)
        }
        guard let regions = try regions(of: Data(contentsOf: source)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try assemble(headerRegion: sealHeader(header, with: cipher, for: url), valueRegion: regions.value)
    }

    /// Reads and decodes an entry file in this format or, without an encryption key, the JSON
    /// format of earlier releases.
    func decodeFile(at url: URL) throws -> EntryFile {
        let data = try Data(contentsOf: url)
        guard let regions = try regions(of: data) else {
            guard cipher == nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
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
        let header = try decodeHeader(regions.header, for: url)
        var value = regions.value
        if let cipher {
            value = try cipher.open(value, as: .value, inFileNamed: url.lastPathComponent)
        }
        return EntryFile(header: header, value: value, isLegacyFormat: false)
    }

    /// Reads an entry file's header without reading its value, except for files in the
    /// JSON format of earlier releases, which are read whole.
    func readHeader(of url: URL) throws -> ScannedFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let headerLength = try headerRegionLength(in: handle.read(upToCount: prefixLength) ?? Data()) else {
            let file = try decodeFile(at: url)
            return ScannedFile(url: url, header: file.header, isLegacyFormat: file.isLegacyFormat)
        }
        let headerData = try handle.read(upToCount: headerLength) ?? Data()
        guard headerData.count == headerLength else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try ScannedFile(url: url, header: decodeHeader(headerData, for: url), isLegacyFormat: false)
    }

    /// Writes a header over the header region of a file in this format, re-sealing it with a
    /// fresh nonce when encrypting.
    ///
    /// - Returns: `false` when the file isn't in this format or the header doesn't fit.
    func overwriteHeader(of url: URL, with header: EntryHeader) throws -> Bool {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        guard let regionLength = try headerRegionLength(in: handle.read(upToCount: prefixLength) ?? Data()) else {
            return false
        }
        let headerData = try encoder.encode(header)
        let capacity = cipher == nil ? regionLength : regionLength - EntryFileCipher.overhead
        guard headerData.count <= capacity else {
            return false
        }
        var region = padded(headerData, to: capacity)
        if let cipher {
            region = try cipher.seal(region, as: .header, inFileNamed: url.lastPathComponent)
        }
        try handle.seek(toOffset: UInt64(prefixLength))
        try handle.write(contentsOf: region)
        return true
    }

    /// The bytes that start every entry file written in this format.
    private var signature: Data {
        cipher == nil ? entryFileSignature : encryptedEntryFileSignature
    }

    /// The length of the signature and the header region's length that start a file in this format.
    private var prefixLength: Int {
        signature.count + MemoryLayout<UInt32>.size
    }

    /// The header region's length stated at the start of a file in this format, or `nil` when
    /// the data doesn't start like one.
    private func headerRegionLength(in data: Data) -> Int? {
        guard data.count >= prefixLength, data.starts(with: signature) else {
            return nil
        }
        return data.dropFirst(signature.count).prefix(MemoryLayout<UInt32>.size).reduce(0) { $0 << 8 | Int($1) }
    }

    /// The header region and value region of a file in this format, or `nil` when the data
    /// doesn't start like one.
    private func regions(of data: Data) throws -> (header: Data, value: Data)? {
        guard let headerLength = headerRegionLength(in: data) else {
            return nil
        }
        let headerStart = data.startIndex + prefixLength
        let headerEnd = headerStart + headerLength
        guard data.endIndex >= headerEnd else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (Data(data[headerStart ..< headerEnd]), Data(data[headerEnd...]))
    }

    /// Decodes the header region of the entry file at a location, opening it first when encrypting.
    private func decodeHeader(_ region: Data, for url: URL) throws -> EntryHeader {
        guard let cipher else {
            return try decoder.decode(EntryHeader.self, from: region)
        }
        return try decoder.decode(EntryHeader.self, from: cipher.open(region, as: .header, inFileNamed: url.lastPathComponent))
    }

    /// Seals a JSON header padded with spaces to a whole number of buckets, leaving room for metadata updates.
    private func sealHeader(_ header: EntryHeader, with cipher: EntryFileCipher, for url: URL) throws -> Data {
        let headerData = try encoder.encode(header)
        let bucketCount = (headerData.count + entryHeaderPadding + entryHeaderBucketSize - 1) / entryHeaderBucketSize
        return try cipher.seal(padded(headerData, to: bucketCount * entryHeaderBucketSize), as: .header, inFileNamed: url.lastPathComponent)
    }

    /// An entry file: the signature, the header region's length as a big-endian `UInt32`, the
    /// header region, then the value region.
    private func assemble(headerRegion: Data, valueRegion: Data) -> Data {
        var data = signature
        withUnsafeBytes(of: UInt32(headerRegion.count).bigEndian) { data.append(contentsOf: $0) }
        return data + headerRegion + valueRegion
    }

    /// Data followed by spaces up to a length.
    private func padded(_ data: Data, to length: Int) -> Data {
        data + Data(repeating: UInt8(ascii: " "), count: length - data.count)
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
        entryFileName(digest: SHA256.hash(data: Data(precomposedStringWithCanonicalMapping.utf8)))
    }
}

/// An entry file name made of a digest in lowercase hex.
func entryFileName(digest: some Sequence<UInt8>) -> String {
    digest.map { String(format: "%02x", $0) }.joined() + ".cache_entry"
}
