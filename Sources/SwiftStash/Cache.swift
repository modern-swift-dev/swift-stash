import Foundation

/// A `Sendable` type that can be stored in a ``Cache``.
@available(*, deprecated, renamed: "Sendable")
public typealias CacheableDataType = Sendable

/// The order used to evict entries from a ``Cache``, and the age at which entries expire.
public enum EvictionPolicy: Sendable, Equatable {

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

/// An actor-isolated cache backed by a storage engine.
///
/// The cache loads entries from its storage engine during initialization and persists additions
/// and removals through that engine. With the LRU policy, it also persists the access date of each read. Use an ``EvictionPolicy`` to choose the
/// order used when reducing the cache to a maximum number of entries.
///
/// Example usage:
/// ```swift
/// let cache = Cache(
///     policy: .lru(threshold: 300),
///     storageEngine: MemoryStorageEngine<String, String>()
/// )
/// await cache.add("value", for: "key")
/// let value = await cache["key"]
/// ```
public actor Cache<StorageEngineType: StorageEngine, CacheType: Sendable> where StorageEngineType.StoredType == CacheType {

    /// The type used to identify entries in this cache.
    public typealias KeyType = StorageEngineType.KeyType

    /// The order used to evict entries from the cache.
    public typealias EvictionPolicy = SwiftStash.EvictionPolicy

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

    /// The maximum number of entries kept after each addition, if any
    private let maxCount: Int?

    /// The Entries
    private var entries: [KeyType: CacheEntry<KeyType, CacheType>] = [:]

    /// Creates a cache and loads any entries provided by its storage engine.
    ///
    /// - Parameters:
    ///   - policy: The policy used by ``evictExpired()`` and ``evictUntil(maxCount:)``. Defaults to LRU with a 300-second threshold.
    ///   - storageEngine: The storage engine that loads and persists cache entries.
    ///   - clock: The clock used to timestamp entries and find expired ones. Defaults to ``NetworkTimeClock/shared``.
    ///   - maxCount: The maximum number of entries to keep. After each addition, the cache calls
    ///     ``evictUntil(maxCount:)`` with this value when it holds more entries. Pass `nil`, the default,
    ///     to keep any number of entries. Entries loaded from storage aren't evicted until the next addition.
    public init(
        policy: EvictionPolicy = .lru(threshold: 300),
        storageEngine: StorageEngineType,
        clock: any CacheClock = NetworkTimeClock.shared,
        maxCount: Int? = nil
    ) {
        self.policy = policy
        self.clock = clock
        self.maxCount = maxCount
        self.storageEngine = storageEngine
        var loaded: [KeyType: CacheEntry<KeyType, CacheType>] = [:]
        for entry in storageEngine.load() {
            loaded[entry.key] = entry
        }
        entries = loaded
    }

    /// Creates a cache and loads any entries provided by its storage engine.
    @available(*, deprecated, renamed: "init(policy:storageEngine:clock:)")
    public init(
        policy: EvictionPolicy = .lru(threshold: 300),
        storagePolicy: StorageEngineType,
        clock: any CacheClock = NetworkTimeClock.shared
    ) {
        self.init(policy: policy, storageEngine: storagePolicy, clock: clock)
    }

    /// Returns all keys currently held by the cache.
    ///
    /// The keys include expired entries that haven't been read or evicted yet.
    ///
    /// - Returns: An unordered array of cache keys.
    public func keys() -> [KeyType] {
        Array(entries.keys)
    }

    /// Returns all unexpired values held by the cache.
    ///
    /// Listing values doesn't record an access to each entry, so it doesn't change LRU
    /// eviction order or extend LRU lifetimes. Expired entries are removed instead of returned.
    ///
    /// - Returns: An unordered array of cached values.
    public func values() -> [CacheType] {
        let now = clock.now
        let expiredKeys = entries.values.compactMap { isExpired($0, at: now) ? $0.key : nil }
        for key in expiredKeys {
            remove(key)
        }
        return entries.values.map(\.value)
    }

    /// Returns the entry for a key and records an access when it exists.
    ///
    /// An expired entry is removed instead of returned.
    ///
    /// - Parameter key: The key identifying the entry.
    /// - Returns: The matching cache entry, or `nil` when the key is not present or the entry has expired.
    public func entry(for key: KeyType) -> CacheEntry<KeyType, CacheType>? {
        access(key, at: clock.now)
    }

    /// Returns whether the cache holds an unexpired entry for a key.
    ///
    /// Unlike reading the value, this method doesn't record an access, so it doesn't
    /// affect LRU eviction order.
    ///
    /// - Parameter key: The key identifying the entry.
    /// - Returns: `true` when the cache holds an unexpired entry for `key`; otherwise, `false`.
    public func contains(_ key: KeyType) -> Bool {
        guard let entry = entries[key] else {
            return false
        }
        return !isExpired(entry, at: clock.now)
    }

    /// Records an access to an unexpired entry, or removes the entry if it has expired.
    ///
    /// Only the LRU policy depends on access dates, so other policies don't persist accesses.
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
        if case .lru = policy {
            storageEngine.persist(entry)
        }
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
        enforceMaxCount()
    }

    /// Adds a value to the cache for a key.
    ///
    /// An existing entry with the same key is replaced.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key used to retrieve the value.
    /// - Returns: The cache entry created for the value. With a maximum count and the LIFO policy,
    ///   the new entry may be evicted immediately, since LIFO removes the newest entries first.
    @discardableResult public func add(_ value: CacheType, for key: KeyType) -> CacheEntry<KeyType, CacheType> {
        let now = clock.now
        let entry = CacheEntry(key: key, value: value, creation: now, lastAccess: now)
        entries[key] = entry
        storageEngine.persist(entry)
        enforceMaxCount()
        return entry
    }

    /// Evicts entries when the cache holds more than its maximum count.
    private func enforceMaxCount() {
        if let maxCount, entries.count > maxCount {
            evictUntil(maxCount: maxCount)
        }
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
    /// Reading an existing value updates its last-access date. With the LRU policy, the updated
    /// entry is also persisted, so the access survives a reload.
    /// Reading an expired value removes its entry and returns `nil`.
    ///
    /// The setter is deprecated because code outside the cache's actor can't assign through it.
    /// Use ``add(_:for:)`` and ``remove(_:)`` instead.
    ///
    /// - Parameter key: The key of the entry to access.
    /// - Returns: The cached value, or `nil` if the key is not present.
    public subscript(key: KeyType) -> CacheType? {
        get {
            access(key, at: clock.now)?.value
        }
        @available(*, deprecated, message: "Use add(_:for:) or remove(_:).")
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
    /// policy determines which entries are removed first. Entries with equal dates, such as
    /// those added together in one batch, are ordered by their keys' string values:
    /// FIFO and LRU remove the lowest keys first, and LIFO removes the highest keys first.
    ///
    /// - Parameter maxCount: The maximum number of entries to retain.
    /// - Returns: The number of entries remaining in the cache.
    @discardableResult public func evictUntil(maxCount: Int) -> Int {

        // if specified max size is 0, then clear it
        guard maxCount > 0 else {
            clear()
            return 0
        }

        // Start by flushing old entries
        evictExpired()

        // if the number of entries is still over, when we need to delete more entries
        guard entries.count > maxCount else {
            return entries.count
        }

        // Calculate the nb entries to delete
        let nbEntriesToDelete = entries.count - maxCount

        // Evict according to the eviction policy
        let values = entries.values.sorted(by: evictsBefore).prefix(nbEntriesToDelete)
        for value in values {
            if let entry = entries.removeValue(forKey: value.key) {
                storageEngine.delete(entry)
            }
        }

        return entries.count
    }

    /// Removes expired entries, then evicts entries until the cache contains at most a given number of items.
    @available(*, deprecated, renamed: "evictUntil(maxCount:)")
    @discardableResult public func evictUntil(maxNbItems max: Int) -> Int {
        evictUntil(maxCount: max)
    }

    /// Whether the eviction policy removes one entry before another.
    ///
    /// Entries with equal dates are ordered by their keys' string values, so the order
    /// doesn't depend on dictionary iteration order.
    private func evictsBefore(_ lhs: CacheEntry<KeyType, CacheType>, _ rhs: CacheEntry<KeyType, CacheType>) -> Bool {
        switch policy {
            case .fifo:
                (lhs.creation, lhs.key.stringValue) < (rhs.creation, rhs.key.stringValue)
            case .lifo:
                (lhs.creation, lhs.key.stringValue) > (rhs.creation, rhs.key.stringValue)
            case .lru:
                (lhs.lastAccess, lhs.key.stringValue) < (rhs.lastAccess, rhs.key.stringValue)
        }
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
