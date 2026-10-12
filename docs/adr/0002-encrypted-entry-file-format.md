# Encrypted entry file format

When given an encryption key, the disk storage engine encrypts the whole entry file, including the entry header and its cache key, and names each file with a keyed HMAC of the cache key instead of a plain SHA-256, because for apps such as banking apps the cache key itself (often containing account identifiers) is sensitive and a plain hash can be confirmed by guessing. Content and filename subkeys are derived from the encryption key with HKDF so one key isn't used by two algorithms. The entry header and the value are sealed in two separate AES-256-GCM boxes, each bound to its file through associated data, and the header is padded to a fixed-size bucket so its length doesn't reveal the cache key's length.

Files the engine can't decrypt (plaintext, legacy-format, sealed with a different encryption key, or failing authentication) are deleted rather than migrated, as is every encrypted file found by an engine without an encryption key.

## Considered Options

- **Encrypting only the value**, as a serializer wrapper: rejected because it leaves cache keys and metadata readable on disk.
- **Sealing the whole file in one box**: rejected because every LRU read would then rewrite the whole file, undoing in-place entry header updates.
- **Migrating plaintext files to the encrypted format**: rejected because the plaintext would remain on disk until migrated, and a cache can afford to lose entries.

## Consequences

- Value sizes remain visible on disk.
- Rotating or losing the encryption key empties the cache.
- An engine created without the encryption key for a directory of encrypted entry files deletes them.
