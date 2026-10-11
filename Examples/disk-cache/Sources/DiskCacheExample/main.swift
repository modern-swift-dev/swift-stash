import Foundation
import SwiftStash

private struct Profile: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
}

@main private enum DiskCacheExample {
    static func main() async throws {
        let directoryName = "profile-example"

        let storage = DiskStorageEngine(
            directory: directoryName,
            serializer: JsonDiskStorageSerializer<Profile>()
        )
        let cache = Cache(
            policy: .lru(threshold: 24 * 60 * 60),
            storagePolicy: storage
        )

        let profile = Profile(id: "42", displayName: "Ada")
        await cache.add(profile)

        if let cachedProfile = await cache[profile.id] {
            print("Loaded from disk-backed cache: \(cachedProfile.displayName)")
        }
    }
}
