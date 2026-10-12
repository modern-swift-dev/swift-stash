---
title: "Encrypting entries on disk | SwiftStash"
description: "Encrypt disk cache entries with an encryption key your app supplies, and understand what that protects."
---

<a id="main-content"></a>

Encrypting entries on disk

# Keep cached data unreadable without your encryption key.

Pass an encryption key to `DiskStorageEngine` and every entry file is encrypted at the application layer. Nothing on disk reveals which cache keys exist, their values, or their entry metadata. SwiftStash never creates or stores the encryption key. Your app decides how to create it, protect it, and when to rotate it.

## Turn encryption on

Every `DiskStorageEngine` initializer takes an optional `encryptionKey`. The encryption key must be at least 256 bits long. A shorter one stops the process, in debug and release builds alike, so a weak encryption key can't ship unnoticed.

Swift

```swift
import CryptoKit
import SwiftStash

let storage = DiskStorageEngine(
    directory: "accounts",
    keyType: AccountKey.self,
    serializer: JsonDiskStorageSerializer<Account>(),
    options: [.atomic, .completeFileProtection],
    encryptionKey: try CacheEncryptionKeyStore.encryptionKey()
)
let cache = Cache(storageEngine: storage)
```

Encryption works with any serializer and any writing options. Without an encryption key, the engine behaves exactly as before. On Linux, Android, and Windows, `SymmetricKey` comes from [swift-crypto](https://github.com/apple/swift-crypto), which SwiftStash doesn't re-export. Add it to your package for the platforms without CryptoKit, with a version range that overlaps SwiftStash's, and import it in place of CryptoKit, as the [encrypted disk cache example](/docs/swift-stash/examples/#encrypted-disk-cache) does.

Package.swift

```swift
.product(
    name: "Crypto",
    package: "swift-crypto",
    condition: .when(platforms: [.linux, .android, .windows, .openbsd, .wasi])
)
```

Swift

```swift
#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif
```

## What gets encrypted

- **Values:** each value is sealed with AES-256-GCM after the serializer converts it to bytes.
- **Cache keys and entry metadata:** the entry header, which holds the cache key and the creation, last-access, and expiration dates, access count, and cost, is sealed separately. It's padded to a multiple of 256 bytes, so its size reveals the cache key's length only in 256-byte steps.
- **Filenames:** each entry file is named with an HMAC-SHA256 of its cache key. Without the encryption key, nobody can confirm a cache key is stored by hashing a guess.

Every sealed region is authenticated and bound to its entry file. The engine never returns a value from a modified entry file, or from regions moved between entry files. It deletes those files instead.

Reads stay fast. Creating a cache decrypts only entry headers, and values are decrypted on first use. With the LRU policy, a read re-seals only the entry header, and never encrypts or serializes the value again.

## Threat model

Encryption protects data at rest:

- **Forensic extraction.** Under the default file protection class, files stay readable once a device has been unlocked after boot, including by forensic extraction tools. Encrypted entry files remain unreadable without your encryption key.
- **Platforms without sandbox encryption.** On Linux, Android, and Windows, the operating system doesn't guarantee encryption at rest.
- **Audit requirements.** Compliance frameworks such as OWASP MASVS-STORAGE and PCI DSS, and internal security audits, often require application-layer encryption of data at rest, whatever the operating system provides.

It doesn't protect against:

- **A compromised running process.** Code running inside your app can read the encryption key, the cache, and its decrypted values in memory.
- **The Keychain on a jailbroken device.** An attacker who can read the Keychain can read the encryption key stored in it.
- **Rollback.** An attacker can replace an entry file with an older copy that the same encryption key sealed. The cache then returns the older value and entry metadata.
- **Sizes and counts.** Value sizes and the number of entries remain visible on disk.

## Recommended practices

- **Use a random 256-bit encryption key.** Create it with `SymmetricKey(size: .bits256)`. Don't derive it from a password or reuse an encryption key that protects other data.
- **Combine encryption with `.completeFileProtection`.** Pass it in the engine's `options` so iOS also encrypts entry files with a file-protection key that's unavailable while the device is locked.
- **Expect misses while the device is locked.** With `.completeFileProtection`, entry files can't be opened while the device is locked. The engine leaves them in place, and the cache treats their entries as missing: a read returns `nil` and forgets the entry until the cache is next created. A cache first used while the device is locked starts without them. Create the cache after the device is unlocked when background work needs its entries.
- **Store the encryption key in the Keychain,** with an accessibility class that keeps it on this device, such as `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

## Changing or deleting the encryption key

The engine deletes any entry file it can't decrypt, and never migrates one. So:

- **Rotating the encryption key empties the cache.** Entry files sealed with the previous encryption key are deleted when the cache directory is scanned, so rotating the encryption key needs no migration code.
- **Omitting the encryption key empties the cache.** An engine created without an encryption key deletes the encrypted entry files it finds. An engine created with one deletes plaintext entry files, including files written before you turned encryption on.
- **Deleting the encryption key crypto-shreds the cache.** Once the encryption key is gone, no one can read the entry files. For example, on logout, delete the encryption key, then call `clear()` on the cache to release its entries from memory and remove the files.

## Sample code: store an encryption key in the Keychain

> **Sample code, not API.** SwiftStash doesn't include this type. Adapt it to your security team's policy, for example Secure Enclave wrapping, biometric gating, or a server-derived encryption key.

This sample loads the cache's encryption key from the Keychain and creates it on first use. The `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility class means the encryption key never leaves this device, and is unavailable while the device is locked. While the device is locked, `encryptionKey()` throws instead of returning the encryption key; treat that as a signal not to create the cache.

Swift

```swift
import CryptoKit
import Foundation
import Security

/// Sample code: loads the cache's encryption key from the Keychain, creating it on first use.
enum CacheEncryptionKeyStore {
    struct KeychainError: Error {
        let status: OSStatus
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.example.app.cache-encryption-key",
            kSecAttrAccount as String: "SwiftStash",
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func encryptionKey() throws -> SymmetricKey {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }

        let encryptionKey = SymmetricKey(size: .bits256)
        var item = query
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecValueData as String] = encryptionKey.withUnsafeBytes { Data($0) }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Another caller stored an encryption key first; use theirs.
            return try self.encryptionKey()
        }
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
        return encryptionKey
    }

    /// Makes every entry encrypted with this encryption key permanently unreadable.
    static func deleteEncryptionKey() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
```
