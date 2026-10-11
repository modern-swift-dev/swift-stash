import Foundation

/// A `Sendable` type that can be stored in a ``Cache``.
public typealias CacheableDataType = Sendable

/// An actor-isolated cache backed by a storage engine.
///
/// The cache loads entries from its storage engine during initialization and persists additions,
/// reads, and removals through that engine. Use an ``EvictionPolicy`` to choose the
/// order used when reducing the cache to a maximum number of entries.
///
/// Example usage:
/// ```swift
/// let cache = await Cache(
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
    ///
    /// The count includes expired entries that haven't been read or evicted yet.
    public var count: Int {
        entries.count
    }

    /// The Storage Policy
    private let storageEngine: StorageEngineType

    /// The Eviction Policy
    private let policy: EvictionPolicy

    /// The clock used to timestamp entries and find expired ones
    private let clock: any CacheClock

    /// The Entries
    private var entries: [KeyType: CacheEntry<KeyType, CacheType>] = [:]

    /// Creates a cache and loads any entries provided by its storage engine.
    ///
    /// - Parameters:
    ///   - policy: The policy used by ``evictExpired()`` and ``evictUntil(maxNbItems:)``. Defaults to LRU with a 300-second threshold.
    ///   - storagePolicy: The storage engine that loads and persists cache entries.
    ///   - clock: The clock used to timestamp entries and find expired ones. Defaults to ``NetworkTimeClock/shared``.
    public init(
        policy: EvictionPolicy = .lru(threshold: 300),
        storagePolicy: StorageEngineType,
        clock: any CacheClock = NetworkTimeClock.shared
    ) async {
        self.policy = policy
        self.clock = clock
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
    /// The keys include expired entries that haven't been read or evicted yet.
    ///
    /// - Returns: An unordered array of cache keys.
    public func keys() -> [KeyType] {
        Array(entries.keys)
    }

    /// Returns all unexpired values held by the cache and persists an access for each entry.
    ///
    /// Expired entries are removed instead of returned.
    ///
    /// - Returns: An unordered array of cached values.
    public func values() -> [CacheType] {
        let now = clock.now
        return entries.keys.compactMap { access($0, at: now)?.value }
    }

    /// Returns the entry for a key and persists an access when it exists.
    ///
    /// An expired entry is removed instead of returned.
    ///
    /// - Parameter key: The key identifying the entry.
    /// - Returns: The matching cache entry, or `nil` when the key is not present or the entry has expired.
    public func entry(for key: KeyType) -> CacheEntry<KeyType, CacheType>? {
        access(key, at: clock.now)
    }

    /// Records an access to an unexpired entry, or removes the entry if it has expired.
    private func access(_ key: KeyType, at now: Date) -> CacheEntry<KeyType, CacheType>? {
        guard var entry = entries[key] else {
            return nil
        }
        guard !isExpired(entry, at: now) else {
            remove(key)
            return nil
        }
        entry.updateLastAccess(at: now)
        entries[key] = entry
        storageEngine.persist(entry)
        return entry
    }

    /// Whether an entry's age meets or exceeds the eviction policy's threshold.
    private func isExpired(_ entry: CacheEntry<KeyType, CacheType>, at now: Date) -> Bool {
        switch policy {
            case let .fifo(threshold),
                 let .lifo(threshold):
                entry.creation <= Date(timeInterval: -threshold, since: now)
            case let .lru(threshold):
                entry.lastAccess <= Date(timeInterval: -threshold, since: now)
        }
    }

    /// Adds multiple values to the cache using their corresponding keys.
    ///
    /// All entries in the batch receive the same creation and last-access time.
    ///
    /// - Parameter values: Key-value pairs to add. An existing entry with the same key is replaced.
    public func add(_ values: [(KeyType, CacheType)]) {
        let creation = clock.now
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
        let now = clock.now
        let entry = CacheEntry(key: key, value: value, creation: now, lastAccess: now)
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
    /// Reading an expired value removes its entry and returns `nil`.
    /// Assigning `nil` removes the entry; assigning a non-`nil` value creates or replaces it.
    ///
    /// - Parameter key: The key of the entry to access.
    /// - Returns: The cached value, or `nil` if the key is not present.
    public subscript(key: KeyType) -> CacheType? {
        get {
            access(key, at: clock.now)?.value
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
        let now = clock.now
        let expiredKeys = entries.values.compactMap { isExpired($0, at: now) ? $0.key : nil }
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
