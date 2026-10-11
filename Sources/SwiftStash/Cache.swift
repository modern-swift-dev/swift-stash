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
/// and removals through that engine. With the LRU policy, it also persists the access date of each read.
/// When the engine supports it, values are read from storage the first time they're needed and then
/// kept in memory until ``unloadValues()`` releases them. Use an ``EvictionPolicy`` to choose the
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
public actor Cache<StorageEngineType: StorageEngine> {

    /// The type used to identify entries in this cache.
    public typealias KeyType = StorageEngineType.KeyType

    /// The type of values stored in this cache.
    public typealias CacheType = StorageEngineType.StoredType

    /// The order used to evict entries from the cache.
    public typealias EvictionPolicy = SwiftStash.EvictionPolicy

    /// A Boolean value indicating whether the cache contains no entries.
    public var isEmpty: Bool {
        loadIfNeeded()
        return slots.isEmpty
    }

    /// The number of entries currently held by the cache.
    ///
    /// The count includes expired entries that haven't been read or evicted yet.
    public var count: Int {
        loadIfNeeded()
        return slots.count
    }

    /// The total cost of the entries currently held by the cache, or `0` when the cache has no cost limit.
    public var totalCost: Int {
        loadIfNeeded()
        return loadedTotalCost
    }

    /// The executor that runs the cache's work, including its storage engine's I/O, on a serial queue
    nonisolated let executor = CacheExecutor(label: "SwiftStash.Cache")

    /// The executor that runs the cache's work.
    ///
    /// Each cache runs on its own serial dispatch queue, so blocking storage I/O doesn't occupy
    /// a thread of Swift's cooperative thread pool.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    /// The total cost of the entries in `slots`
    private var loadedTotalCost = 0

    /// Whether the entries have been loaded from the storage engine
    private var hasLoaded = false

    /// The Storage Policy
    private let storageEngine: StorageEngineType

    /// The Eviction Policy
    private let policy: EvictionPolicy

    /// The clock used to timestamp entries and find expired ones
    private let clock: any CacheClock

    /// The maximum number of entries kept after each addition, if any
    private let maxCount: Int?

    /// The maximum total cost kept after each addition, if any
    private let costLimit: CostLimit<CacheType>?

    /// Whether the storage engine loads values on demand, so values can be released from memory
    private var loadsValuesLazily = false

    /// The entries, each with its value once loaded
    private var slots: [KeyType: Slot] = [:]

    /// An entry's metadata, and its value once loaded from storage
    private struct Slot {
        var metadata: CacheEntryMetadata<KeyType>
        var value: CacheType?
    }

    /// Creates a cache that loads the entries provided by its storage engine.
    ///
    /// The cache loads entries from its storage engine on its own queue when it's first used, so
    /// creating a cache doesn't perform I/O. When the storage engine supports it, as
    /// ``DiskStorageEngine`` does, the cache loads only the entries' metadata and reads each
    /// value from storage the first time it's needed.
    ///
    /// - Parameters:
    ///   - policy: The policy used by ``evictExpired()`` and ``evictUntil(maxCount:)``. Defaults to LRU with a 300-second threshold.
    ///   - storageEngine: The storage engine that loads and persists cache entries.
    ///   - clock: The clock used to timestamp entries and find expired ones. Defaults to ``NetworkTimeClock/shared``.
    ///   - maxCount: The maximum number of entries to keep. After each addition, the cache calls
    ///     ``evictUntil(maxCount:)`` with this value when it holds more entries. Pass `nil`, the default,
    ///     to keep any number of entries. Entries loaded from storage aren't evicted until the next addition.
    ///   - costLimit: The maximum total cost of the entries, and how to compute each value's cost.
    ///     After each addition, the cache removes expired entries and then evicts entries in policy
    ///     order until the total cost is within the limit. Pass `nil`, the default, for no limit.
    ///     Entries loaded from storage aren't evicted until the next addition. Entries whose values
    ///     haven't been loaded count with the cost recorded when they were stored; values stored
    ///     by a cache without a cost limit are loaded with the entries to compute their cost.
    public init(
        policy: EvictionPolicy = .lru(threshold: 300),
        storageEngine: StorageEngineType,
        clock: any CacheClock = NetworkTimeClock.shared,
        maxCount: Int? = nil,
        costLimit: CostLimit<CacheType>? = nil
    ) {
        self.policy = policy
        self.clock = clock
        self.maxCount = maxCount
        self.costLimit = costLimit
        self.storageEngine = storageEngine
    }

    /// Loads the entries from the storage engine the first time the cache is used.
    private func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        var loaded: [KeyType: Slot] = [:]
        if let metadata = storageEngine.loadMetadata() {
            loadsValuesLazily = true
            for var entry in metadata {
                var value: CacheType?
                if let costLimit, entry.cost == nil {
                    // Stored without a cost limit, so the value is needed to compute its cost.
                    guard let loadedValue = storageEngine.loadValue(for: entry.key) else {
                        continue
                    }
                    value = loadedValue
                    entry.cost = costLimit.cost(of: loadedValue)
                } else if costLimit == nil {
                    entry.cost = nil
                }
                loaded[entry.key] = Slot(metadata: entry, value: value)
            }
        } else {
            loadsValuesLazily = false
            for entry in storageEngine.load() {
                var metadata = entry.metadata
                metadata.cost = costLimit?.cost(of: entry.value)
                loaded[entry.key] = Slot(metadata: metadata, value: entry.value)
            }
        }
        slots = loaded
        loadedTotalCost = loaded.values.reduce(0) { $0 + ($1.metadata.cost ?? 0) }
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
        loadIfNeeded()
        return Array(slots.keys)
    }

    /// Returns all unexpired values held by the cache.
    ///
    /// Listing values doesn't record an access to each entry, so it doesn't change LRU
    /// eviction order or extend LRU lifetimes. Expired entries are removed instead of returned.
    /// Values that haven't been loaded yet are read from storage; entries whose values can't
    /// be read are removed.
    ///
    /// - Returns: An unordered array of cached values.
    public func values() -> [CacheType] {
        loadIfNeeded()
        evictExpired()
        return Array(slots.keys).compactMap { loadedValue(for: $0) }
    }

    /// Returns the entry for a key and records an access when it exists.
    ///
    /// An expired entry is removed instead of returned.
    ///
    /// - Parameter key: The key identifying the entry.
    /// - Returns: The matching cache entry, or `nil` when the key is not present or the entry has expired.
    public func entry(for key: KeyType) -> CacheEntry<KeyType, CacheType>? {
        loadIfNeeded()
        return access(key, at: clock.now)
    }

    /// Returns whether the cache holds an unexpired entry for a key.
    ///
    /// Unlike reading the value, this method doesn't record an access, so it doesn't
    /// affect LRU eviction order, and it doesn't load the value from storage.
    ///
    /// - Parameter key: The key identifying the entry.
    /// - Returns: `true` when the cache holds an unexpired entry for `key`; otherwise, `false`.
    public func contains(_ key: KeyType) -> Bool {
        loadIfNeeded()
        guard let slot = slots[key] else {
            return false
        }
        return !isExpired(slot.metadata, at: clock.now)
    }

    /// Releases the values held in memory that the storage engine can load again on demand.
    ///
    /// Entries stay in the cache, and their values are read from storage the next time they're
    /// needed. Call this method to reduce memory use, for example when the system reports
    /// memory pressure. It has no effect when the storage engine can't load values on demand,
    /// as with ``MemoryStorageEngine``.
    public func unloadValues() {
        loadIfNeeded()
        guard loadsValuesLazily else {
            return
        }
        for key in slots.keys {
            slots[key]?.value = nil
        }
    }

    /// Records an access to an unexpired entry, or removes the entry if it has expired.
    ///
    /// Only the LRU policy depends on access dates, so other policies don't persist accesses.
    private func access(_ key: KeyType, at now: Date) -> CacheEntry<KeyType, CacheType>? {
        guard let slot = slots[key] else {
            return nil
        }
        guard !isExpired(slot.metadata, at: now) else {
            remove(key)
            return nil
        }
        guard let value = loadedValue(for: key), var metadata = slots[key]?.metadata else {
            return nil
        }
        metadata.updateLastAccess(at: now)
        slots[key]?.metadata = metadata
        let entry = CacheEntry(metadata: metadata, value: value)
        if case .lru = policy, !storageEngine.persistMetadata(metadata) {
            storageEngine.persist(entry)
        }
        return entry
    }

    /// Returns an entry's value, loading it from storage if needed.
    ///
    /// An entry whose value can't be loaded is removed.
    private func loadedValue(for key: KeyType) -> CacheType? {
        guard var slot = slots[key] else {
            return nil
        }
        if let value = slot.value {
            return value
        }
        guard let value = storageEngine.loadValue(for: key) else {
            remove(key)
            return nil
        }
        slot.value = value
        if let costLimit {
            let cost = costLimit.cost(of: value)
            loadedTotalCost += cost - (slot.metadata.cost ?? 0)
            slot.metadata.cost = cost
        }
        slots[key] = slot
        return value
    }

    /// Whether an entry has reached its own expiration date or the eviction policy's threshold.
    private func isExpired(_ entry: CacheEntryMetadata<KeyType>, at now: Date) -> Bool {
        if let expiration = entry.expiration, expiration <= now {
            return true
        }
        return switch policy {
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
    /// - Parameters:
    ///   - values: Key-value pairs to add. An existing entry with the same key is replaced.
    ///   - lifetime: The number of seconds after which the entries expire, even if the eviction
    ///     policy's threshold hasn't been reached. Pass `nil`, the default, to rely on the policy alone.
    public func add(_ values: [(KeyType, CacheType)], expiresAfter lifetime: TimeInterval? = nil) {
        loadIfNeeded()
        let creation = clock.now
        let expiration = lifetime.map { creation.addingTimeInterval($0) }
        for value in values {
            let entry = CacheEntry(
                key: value.0,
                value: value.1,
                creation: creation,
                lastAccess: creation,
                expiration: expiration,
                cost: costLimit?.cost(of: value.1)
            )
            store(entry)
            storageEngine.persist(entry)
        }
        enforceLimits()
    }

    /// Adds a value to the cache for a key.
    ///
    /// An existing entry with the same key is replaced.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key used to retrieve the value.
    ///   - lifetime: The number of seconds after which the entry expires, even if the eviction
    ///     policy's threshold hasn't been reached. Pass `nil`, the default, to rely on the policy alone.
    /// - Returns: The cache entry created for the value. With a maximum count and the LIFO policy,
    ///   the new entry may be evicted immediately, since LIFO removes the newest entries first.
    @discardableResult public func add(
        _ value: CacheType,
        for key: KeyType,
        expiresAfter lifetime: TimeInterval? = nil
    ) -> CacheEntry<KeyType, CacheType> {
        loadIfNeeded()
        let now = clock.now
        let entry = CacheEntry(
            key: key,
            value: value,
            creation: now,
            lastAccess: now,
            expiration: lifetime.map { now.addingTimeInterval($0) },
            cost: costLimit?.cost(of: value)
        )
        store(entry)
        storageEngine.persist(entry)
        enforceLimits()
        return entry
    }

    /// Inserts or replaces an entry, keeping the total cost up to date.
    private func store(_ entry: CacheEntry<KeyType, CacheType>) {
        loadedTotalCost += (entry.cost ?? 0) - (slots[entry.key]?.metadata.cost ?? 0)
        slots[entry.key] = Slot(metadata: entry.metadata, value: entry.value)
    }

    /// Evicts entries when the cache exceeds its maximum count or cost.
    private func enforceLimits() {
        if let maxCount, slots.count > maxCount {
            evictUntil(maxCount: maxCount)
        }
        if let costLimit, loadedTotalCost > costLimit.maxCost {
            evictExpired()
            for entry in evictionOrder() {
                guard loadedTotalCost > costLimit.maxCost else {
                    break
                }
                remove(entry.key)
            }
        }
    }

    /// Removes the entry for a key from the cache and its storage engine.
    ///
    /// - Parameter key: The key of the entry to remove. A missing key has no effect.
    public func remove(_ key: KeyType) {
        loadIfNeeded()
        guard let slot = slots.removeValue(forKey: key) else {
            return
        }
        loadedTotalCost -= slot.metadata.cost ?? 0
        if let value = slot.value {
            storageEngine.delete(CacheEntry(metadata: slot.metadata, value: value))
        } else {
            storageEngine.delete(forKey: key)
        }
    }

    /// Accesses the value associated with a key.
    ///
    /// Reading an existing value updates its last-access date. With the LRU policy, the updated
    /// metadata is also persisted, so the access survives a reload.
    /// Reading an expired value removes its entry and returns `nil`.
    ///
    /// The setter is deprecated because code outside the cache's actor can't assign through it.
    /// Use ``add(_:for:expiresAfter:)`` and ``remove(_:)`` instead.
    ///
    /// - Parameter key: The key of the entry to access.
    /// - Returns: The cached value, or `nil` if the key is not present.
    public subscript(key: KeyType) -> CacheType? {
        get {
            loadIfNeeded()
            return access(key, at: clock.now)?.value
        }
        @available(*, deprecated, message: "Use add(_:for:) or remove(_:).")
        set {
            loadIfNeeded()
            guard let value = newValue else {
                remove(key)
                return
            }
            add(value, for: key)
        }
    }

    /// Removes all entries from the cache and clears its storage engine.
    public func clear() {
        loadIfNeeded()
        slots.removeAll()
        loadedTotalCost = 0
        storageEngine.clear()
    }

    /// Removes entries that have reached their expiration date or whose age meets or exceeds
    /// the eviction policy's threshold.
    ///
    /// FIFO and LIFO policies compare the creation date; LRU compares the last-access date.
    public func evictExpired() {
        loadIfNeeded()
        let now = clock.now
        let expiredKeys = slots.values.compactMap { isExpired($0.metadata, at: now) ? $0.metadata.key : nil }
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
        loadIfNeeded()

        // if specified max size is 0, then clear it
        guard maxCount > 0 else {
            clear()
            return 0
        }

        // Start by flushing old entries
        evictExpired()

        // if the number of entries is still over, when we need to delete more entries
        guard slots.count > maxCount else {
            return slots.count
        }

        // Evict according to the eviction policy
        for entry in evictionOrder().prefix(slots.count - maxCount) {
            remove(entry.key)
        }

        return slots.count
    }

    /// Removes expired entries, then evicts entries until the cache contains at most a given number of items.
    @available(*, deprecated, renamed: "evictUntil(maxCount:)")
    @discardableResult public func evictUntil(maxNbItems max: Int) -> Int {
        evictUntil(maxCount: max)
    }

    /// The entries' metadata in the order the eviction policy removes them.
    ///
    /// Entries with equal dates are ordered by their keys' string values, so the order
    /// doesn't depend on dictionary iteration order.
    private func evictionOrder() -> [CacheEntryMetadata<KeyType>] {
        slots.values.map(\.metadata).sorted { lhs, rhs in
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
}

// MARK: - Extension for identifiable types
/// Convenience APIs for cache values whose identifiers match the cache key type.
public extension Cache where CacheType: Identifiable, CacheType.ID == KeyType {
    /// Adds an identifiable value using its identifier as the cache key.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - lifetime: The number of seconds after which the entry expires, even if the eviction
    ///     policy's threshold hasn't been reached. Pass `nil`, the default, to rely on the policy alone.
    /// - Returns: The cache entry created for the value.
    @discardableResult func add(_ value: CacheType, expiresAfter lifetime: TimeInterval? = nil) -> CacheEntry<KeyType, CacheType> {
        add(value, for: value.id, expiresAfter: lifetime)
    }
}
