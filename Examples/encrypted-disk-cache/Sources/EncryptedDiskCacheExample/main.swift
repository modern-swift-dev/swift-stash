#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif
import Foundation
import SwiftStash

private struct Account: Codable, Identifiable, Sendable {
    let id: String
    let balance: Int
}

@main private enum EncryptedDiskCacheExample {
    static func main() async throws {
        // A new encryption key on each run makes the previous run's entries unreadable, so the
        // engine deletes them. A real app stores its encryption key, for example in the Keychain.
        let encryptionKey = SymmetricKey(size: .bits256)

        let storage = DiskStorageEngine(
            directory: "encrypted-account-example",
            serializer: JsonDiskStorageSerializer<Account>(),
            encryptionKey: encryptionKey
        )
        let cache = Cache(storageEngine: storage)

        let account = Account(id: "FR7630006000011234567890189", balance: 4200)
        await cache.add(account)

        if let cachedAccount = await cache[account.id] {
            print("Loaded from encrypted disk cache: \(cachedAccount.balance)")
        }
    }
}
