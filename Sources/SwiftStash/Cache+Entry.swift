import Foundation

/// A cached value and the metadata used to manage it.
public struct CacheEntry<KeyType: CacheKey, CachedType: Sendable>: Sendable {

    /// The unique key identifying the cached value.
    public private(set) var key: KeyType

    /// The date when the entry was created.
    public private(set) var creation: Date

    /// The date when the entry was most recently accessed.
    public private(set) var lastAccess: Date

    /// The number of recorded accesses to this entry.
    public private(set) var accessCount: Int64 = 0

    /// The date when the entry expires regardless of the cache's eviction policy, if any.
    public private(set) var expiration: Date?

    /// The entry's cost under the cache's ``CostLimit``, or `nil` when the cache has no cost limit.
    public internal(set) var cost: Int?

    /// The value stored in the entry.
    public private(set) var value: CachedType

    /// Creates a cache entry with the current date of ``NetworkTimeClock/shared`` as its
    /// creation and last-access dates.
    ///
    /// - Parameters:
    ///   - key: The unique key identifying the value.
    ///   - value: The value to store.
    public init(key: KeyType, value: CachedType) {
        let now = NetworkTimeClock.shared.now
        self.init(key: key, value: value, creation: now, lastAccess: now)
    }

    /// Creates a cache entry with explicitly supplied timestamps and access count.
    ///
    /// This initializer is useful when reconstructing an entry loaded from persistent storage.
    ///
    /// - Parameters:
    ///   - key: The unique key identifying the value.
    ///   - value: The value to store.
    ///   - creation: The date when the entry was originally created.
    ///   - lastAccess: The date when the entry was most recently accessed.
    ///   - accessCount: The number of recorded accesses. The default is `0`.
    ///   - expiration: The date when the entry expires regardless of the cache's eviction policy.
    ///     The default is `nil`, meaning only the policy determines when the entry expires.
    ///   - cost: The entry's cost under a ``CostLimit``. The default is `nil`, meaning not computed.
    public init(
        key: KeyType,
        value: CachedType,
        creation: Date,
        lastAccess: Date,
        accessCount: Int64 = 0,
        expiration: Date? = nil,
        cost: Int? = nil
    ) {
        self.key = key
        self.value = value
        self.creation = creation
        self.lastAccess = lastAccess
        self.accessCount = accessCount
        self.expiration = expiration
        self.cost = cost
    }

    /// Records an access at a date.
    mutating func updateLastAccess(at date: Date) {
        lastAccess = date
        if accessCount < .max {
            accessCount += 1
        }
    }
}

/// The metadata of a cache entry, without its value.
///
/// Storage engines that load values on demand return metadata from
/// ``StorageEngine/loadMetadata()``.
public struct CacheEntryMetadata<KeyType: CacheKey>: Sendable {

    /// The unique key identifying the entry.
    public let key: KeyType

    /// The date when the entry was created.
    public let creation: Date

    /// The date when the entry was most recently accessed.
    public private(set) var lastAccess: Date

    /// The number of recorded accesses to the entry.
    public private(set) var accessCount: Int64

    /// The date when the entry expires regardless of the cache's eviction policy, if any.
    public let expiration: Date?

    /// The entry's cost under the cache's ``CostLimit`` when it was stored, or `nil` when it
    /// was stored by a cache without a cost limit.
    public internal(set) var cost: Int?

    /// Creates entry metadata.
    ///
    /// - Parameters:
    ///   - key: The unique key identifying the entry.
    ///   - creation: The date when the entry was created.
    ///   - lastAccess: The date when the entry was most recently accessed.
    ///   - accessCount: The number of recorded accesses. The default is `0`.
    ///   - expiration: The date when the entry expires regardless of the cache's eviction policy.
    ///     The default is `nil`.
    ///   - cost: The entry's cost under a ``CostLimit``. The default is `nil`, meaning not computed.
    public init(
        key: KeyType,
        creation: Date,
        lastAccess: Date,
        accessCount: Int64 = 0,
        expiration: Date? = nil,
        cost: Int? = nil
    ) {
        self.key = key
        self.creation = creation
        self.lastAccess = lastAccess
        self.accessCount = accessCount
        self.expiration = expiration
        self.cost = cost
    }

    /// Records an access at a date.
    mutating func updateLastAccess(at date: Date) {
        lastAccess = date
        if accessCount < .max {
            accessCount += 1
        }
    }
}

extension CacheEntry {

    /// Creates an entry from its metadata and value.
    init(metadata: CacheEntryMetadata<KeyType>, value: CachedType) {
        self.init(
            key: metadata.key,
            value: value,
            creation: metadata.creation,
            lastAccess: metadata.lastAccess,
            accessCount: metadata.accessCount,
            expiration: metadata.expiration,
            cost: metadata.cost
        )
    }

    /// The entry's metadata, without its value.
    var metadata: CacheEntryMetadata<KeyType> {
        CacheEntryMetadata(
            key: key,
            creation: creation,
            lastAccess: lastAccess,
            accessCount: accessCount,
            expiration: expiration,
            cost: cost
        )
    }
}
