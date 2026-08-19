import SwiftStash

private struct Article: Identifiable, Sendable {
    let id: String
    let title: String
}

@main private enum MemoryCacheExample {
    static func main() async {
        let storage = MemoryStorageEngine<Article>()
        let cache = await Cache(
            policy: .lru(threshold: 10 * 60),
            storagePolicy: storage
        )

        await cache.add(Article(id: "swift-concurrency", title: "A tour of Swift concurrency"))
        await cache.add(Article(id: "actors", title: "Protecting state with actors"))

        if let article = await cache["swift-concurrency"] {
            print("Read: \(article.title)")
        }

        let remainingCount = await cache.evictUntil(maxNbItems: 1)
        print("Entries after eviction: \(remainingCount)")
    }
}
