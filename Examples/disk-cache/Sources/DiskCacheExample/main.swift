import Foundation
import SwiftStash

private struct Profile: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
}

@main private enum DiskCacheExample {
    static func main() async throws {
        let directoryName = "profile-example"
        try createCacheDirectory(named: directoryName)

        let storage = DiskStorageEngine(
            directory: directoryName,
            serializer: JsonDiskStorageSerializer<Profile>()
        )
        let cache = await Cache(
            policy: .lru(threshold: 24 * 60 * 60),
            storagePolicy: storage
        )

        let profile = Profile(id: "42", displayName: "Ada")
        await cache.add(profile)

        if let cachedProfile = await cache[profile.id] {
            print("Loaded from disk-backed cache: \(cachedProfile.displayName)")
        }
    }

    private static func createCacheDirectory(named name: String) throws {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app-cache"
        let rootDirectory = URL.cachesDirectory
            .appendingPathComponent("\(bundleIdentifier)-cache")
        let directory = rootDirectory.appendingPathComponent(name)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }
}
