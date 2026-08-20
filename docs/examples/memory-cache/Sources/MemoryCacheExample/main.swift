import SwiftStash

private struct Article: Identifiable, Sendable {
    let id: ArticleKey
    let title: String
}

private enum ArticleKey: String, CacheKey {
    case concurrency
    case actors
}

@main private enum MemoryCacheExample {
    static func main() async {
        let storage = MemoryStorageEngine<ArticleKey, Article>()
        let cache = await Cache(
            policy: .lru(threshold: 10 * 60),
            storagePolicy: storage
        )

        await cache.add(Article(id: .concurrency, title: "A tour of Swift concurrency"))
        await cache.add(Article(id: .actors, title: "Protecting state with actors"))

        if let article = await cache[.concurrency] {
            print("Read: \(article.title)")
        }

        let remainingCount = await cache.evictUntil(maxNbItems: 1)
        print("Entries after eviction: \(remainingCount)")
    }
}
