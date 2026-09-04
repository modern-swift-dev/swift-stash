import Foundation

#if canImport(UIKit) || targetEnvironment(macCatalyst)
import UIKit
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

#if canImport(WatchKit)
import WatchKit
#endif

/// A `Sendable` type that can be stored in a ``Cache``.
public typealias CacheableDataType = Sendable

/// An actor-isolated cache backed by a storage engine.
///
/// The cache loads entries from its storage engine during initialization and persists additions,
/// subscript reads, and removals through that engine. Use an ``EvictionPolicy`` to choose the
/// order used when reducing the cache to a maximum number of entries.
///
/// Example usage:
/// ```swift
/// let cache = Cache(
///     policy: .lru(threshold: 300),
///     storagePolicy: MemoryStorageEngine<String, String>()
/// )
/// await cache.add("value", for: "key")
/// let value = await cache["key"]
/// ```
public actor Cache<StorageEngineType: StorageEngine, CacheType: CacheableDataType> where StorageEngineType.StoredType == CacheType {

    /// The type used to identify entries in this cache.
    public typealias KeyType = StorageEngineType.KeyType

    /// The order used to evict entries from the cache.
    public enum EvictionPolicy {

        /// Evicts entries in first-in, first-out order.
        ///
        /// - Parameter threshold: The maximum age, in seconds, before an entry is considered expired.
        case fifo(threshold: TimeInterval)

        /// Evicts entries in last-in, first-out order.
        ///
        /// - Parameter threshold: The maximum age, in seconds, before an entry is considered expired.
        case lifo(threshold: TimeInterval)

        /// Evicts entries in least-recently-used order.
        ///
        /// - Parameter threshold: The maximum interval, in seconds, since an entry was last accessed before it is considered expired.
        case lru(threshold: TimeInterval)

    }

    /// A Boolean value indicating whether the cache contains no entries.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// The number of entries currently held by the cache.
    public var count: Int {
        entries.count
    }

    /// The Storage Policy
    private let storageEngine: StorageEngineType

    /// The Eviction Policy
    private let policy: EvictionPolicy

    /// The Entries
    private var entries: [KeyType: CacheEntry<KeyType, CacheType>] = [:]

    /// Creates a cache and loads any entries provided by its storage engine.
    ///
    /// - Parameters:
    ///   - policy: The policy used by ``evictExpired()`` and ``evictUntil(maxNbItems:)``. Defaults to LRU with a 300-second threshold.
    ///   - storagePolicy: The storage engine that loads and persists cache entries.
    public init(policy: EvictionPolicy = .lru(threshold: 300), storagePolicy: StorageEngineType) async {
        self.policy = policy
        storageEngine = storagePolicy
        load()
    }

    /// Load entries from storage
    private func load() {
        for entry in storageEngine.load() {
            entries[entry.key] = entry
        }
    }

    /// Returns all keys currently held by the cache.
    ///
    /// - Returns: An unordered array of cache keys.
    public func keys() -> [KeyType] {
        Array(entries.keys)
    }

    /// Returns all values currently held by the cache and records an access for each entry.
    ///
    /// - Returns: An unordered array of cached values.
    public func values() -> [CacheType] {
        var values = [CacheType]()
        for key in entries.keys {
            if var entry = entries[key] {
                entry.updateLastAccess()
                entries[key] = entry
                values.append(entry.value)
            }
        }
        return values
    }

    /// Returns the entry for a key and records an access when it exists.
    ///
    /// - Parameter key: The key identifying the entry.
    /// - Returns: The matching cache entry, or `nil` when the key is not present.
    public func entry(for key: KeyType) -> CacheEntry<KeyType, CacheType>? {
        var entry = entries[key]
        entry?.updateLastAccess()
        entries[key] = entry
        return entry
    }

    /// Adds multiple values to the cache using their corresponding keys.
    ///
    /// All entries in the batch receive the same creation and last-access time.
    ///
    /// - Parameter values: Key-value pairs to add. An existing entry with the same key is replaced.
    public func add(_ values: [(KeyType, CacheType)]) {
        let creation = Date.monotonic
        for value in values {
            let entry = CacheEntry(key: value.0, value: value.1, creation: creation, lastAccess: creation)
            entries[entry.key] = entry
            storageEngine.persist(entry)
        }
    }

    /// Adds a value to the cache for a key.
    ///
    /// An existing entry with the same key is replaced.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key used to retrieve the value.
    /// - Returns: The cache entry created for the value.
    @discardableResult public func add(_ value: CacheType, for key: KeyType) -> CacheEntry<KeyType, CacheType> {
        let entry = CacheEntry(key: key, value: value)
        entries[key] = entry
        storageEngine.persist(entry)
        return entry
    }

    /// Removes the entry for a key from the cache and its storage engine.
    ///
    /// - Parameter key: The key of the entry to remove. A missing key has no effect.
    public func remove(_ key: KeyType) {
        if let entry = entries.removeValue(forKey: key) {
            storageEngine.delete(entry)
        }
    }

    /// Accesses the value associated with a key.
    ///
    /// Reading an existing value updates its last-access date and persists the updated entry.
    /// Assigning `nil` removes the entry; assigning a non-`nil` value creates or replaces it.
    ///
    /// - Parameter key: The key of the entry to access.
    /// - Returns: The cached value, or `nil` if the key is not present.
    public subscript(key: KeyType) -> CacheType? {
        get {
            guard var entry = entries[key] else {
                return nil
            }

            entry.updateLastAccess()
            entries[key] = entry
            storageEngine.persist(entry)
            return entry.value
        }
        set {
            guard let value = newValue else {
                remove(key)
                return
            }
            add(value, for: key)
        }
    }

    /// Removes all entries from the cache and clears its storage engine.
    public func clear() {
        entries.removeAll()
        storageEngine.clear()
    }

    /// Removes entries whose age meets or exceeds the eviction policy's threshold.
    ///
    /// FIFO and LIFO policies compare the creation date; LRU compares the last-access date.
    public func evictExpired() {
        let expiredKeys: [KeyType]
        switch policy {
            case let .fifo(threshold),
                 let .lifo(threshold):
                let deletionDate = Date(timeInterval: -threshold, since: .monotonic)
                expiredKeys = entries.values.compactMap { $0.creation <= deletionDate ? $0.key : nil }
            case let .lru(threshold):
                let deletionDate = Date(timeInterval: -threshold, since: .monotonic)
                expiredKeys = entries.values.compactMap { $0.lastAccess <= deletionDate ? $0.key : nil }
        }
        for key in expiredKeys {
            remove(key)
        }
    }

    /// Removes expired entries, then evicts entries until the cache contains at most a given number of items.
    ///
    /// A nonpositive maximum clears the cache. When further eviction is needed, the configured
    /// policy determines which entries are removed first.
    ///
    /// - Parameter maxNbItems: The maximum number of entries to retain.
    /// - Returns: The number of entries remaining in the cache.
    @discardableResult public func evictUntil(maxNbItems max: Int) -> Int {

        // if specified max size is 0, then clear it
        guard max > 0 else {
            clear()
            return 0
        }

        // Start by flushing old entries
        evictExpired()

        // if the number of entries is still over, when we need to delete more entries
        guard entries.count > max else {
            return entries.count
        }

        // Calculate the nb entries to delete
        let nbEntriesToDelete = entries.count - max

        // Evict according to the eviction policy
        switch policy {
            case .fifo:
                let values = entries.values.sorted { $0.creation < $1.creation }.prefix(nbEntriesToDelete)
                for value in values {
                    if let entry = entries.removeValue(forKey: value.key) {
                        storageEngine.delete(entry)
                    }
                }
            case .lifo:
                let values = entries.values.sorted { $0.creation > $1.creation }.prefix(nbEntriesToDelete)
                for value in values {
                    if let entry = entries.removeValue(forKey: value.key) {
                        storageEngine.delete(entry)
                    }
                }
            case .lru:
                let values = entries.values.sorted { $0.lastAccess < $1.lastAccess }.prefix(nbEntriesToDelete)
                for value in values {
                    if let entry = entries.removeValue(forKey: value.key) {
                        storageEngine.delete(entry)
                    }
                }
        }

        return entries.count
    }
}

// MARK: - Extension for identifiable types
/// Convenience APIs for cache values whose identifiers match the cache key type.
public extension Cache where CacheType: Identifiable, CacheType.ID == KeyType {
    /// Adds an identifiable value using its identifier as the cache key.
    ///
    /// - Parameter value: The value to cache.
    /// - Returns: The cache entry created for the value.
    @discardableResult func add(_ value: CacheType) -> CacheEntry<KeyType, CacheType> {
        add(value, for: value.id)
    }
}
