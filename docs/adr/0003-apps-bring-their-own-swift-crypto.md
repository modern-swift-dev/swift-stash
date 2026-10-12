# Apps on non-Apple platforms depend on swift-crypto themselves

The disk storage engine takes its encryption key as a `SymmetricKey`, which comes from CryptoKit on Apple platforms and from swift-crypto elsewhere. SwiftStash depends on swift-crypto on non-Apple platforms but doesn't re-export it, so an app on Linux, Android, or Windows adds swift-crypto to its own package to create an encryption key. We keep that requirement: the same app code compiles on every platform with `#if canImport(CryptoKit)`, and an app that encrypts its cache needs a crypto library anyway to create or derive its encryption key securely.

## Considered Options

- **Re-exporting swift-crypto from SwiftStash**: rejected because every client on those platforms would see swift-crypto's whole API through `import SwiftStash`, and SwiftStash would then be responsible for it.
- **Accepting the encryption key as raw bytes**: rejected because it adds a second, less type-safe way to pass an encryption key, and apps would still need a crypto library to generate one securely.

## Consequences

- An app's swift-crypto version range must overlap SwiftStash's, so upgrading across a swift-crypto major version needs both to allow it.
- The *Encrypting Entries on Disk* guide and the encrypted disk cache example show the conditional swift-crypto dependency.
