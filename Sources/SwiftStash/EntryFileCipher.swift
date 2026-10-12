import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Seals and names entry files with subkeys derived from an app-supplied encryption key.
///
/// Every seal uses AES-256-GCM with a random 96-bit nonce, including each in-place entry
/// header update. Random nonces stay safe for about 2^32 seals per encryption key, far more
/// than a cache's writes and LRU updates reach in practice.
struct EntryFileCipher {

    /// The part of an entry file a sealed region holds.
    ///
    /// Each region's associated data includes its role, so a sealed entry header can't be
    /// opened as a sealed value or the other way around.
    enum Role: UInt8 {
        case header = 1
        case value = 2
    }

    /// The subkey that seals entry headers and values
    private let contentKey: SymmetricKey

    /// The subkey that authenticates cache keys into entry file names
    private let fileNameKey: SymmetricKey

    init(encryptionKey: SymmetricKey) {
        contentKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: encryptionKey,
            info: Data("SwiftStash entry file content".utf8),
            outputByteCount: 32
        )
        fileNameKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: encryptionKey,
            info: Data("SwiftStash entry file name".utf8),
            outputByteCount: 32
        )
    }

    /// An HMAC-SHA256 of the canonically composed cache key, so equivalent spellings share a
    /// file and names can't be confirmed by hashing a guessed cache key.
    func fileName(for key: String) -> String {
        entryFileName(digest: HMAC<SHA256>.authenticationCode(for: Data(key.precomposedStringWithCanonicalMapping.utf8), using: fileNameKey))
    }

    /// Seals a region of the entry file with a given name: the nonce, the ciphertext, then the tag.
    func seal(_ data: Data, as role: Role, inFileNamed fileName: String) throws -> Data {
        let box = try AES.GCM.seal(data, using: contentKey, authenticating: associatedData(role, fileName))
        guard let combined = box.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return combined
    }

    /// Opens a region sealed for the entry file with a given name.
    ///
    /// - Throws: An error when the region was sealed with another encryption key, for another
    ///   file or role, or has been modified.
    func open(_ sealed: Data, as role: Role, inFileNamed fileName: String) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: contentKey, authenticating: associatedData(role, fileName))
    }

    /// Binds a sealed region to the format, its role, and its entry file.
    private func associatedData(_ role: Role, _ fileName: String) -> Data {
        encryptedEntryFileSignature + [role.rawValue] + Data(fileName.utf8)
    }
}
