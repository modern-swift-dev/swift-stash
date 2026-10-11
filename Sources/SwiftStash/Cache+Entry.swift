import Foundation

/// A cached value and the metadata used to manage it.
public struct CacheEntry<KeyType: CacheKey, CachedType: CacheableDataType>: Sendable {

    /// The unique key identifying the cached value.
    public private(set) var key: KeyType

    /// The date when the entry was created.
    public private(set) var creation: Date

    /// The date when the entry was most recently accessed.
    public private(set) var lastAccess: Date

    /// The number of recorded accesses to this entry.
    public private(set) var accessCount: Int64 = 0

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

    /// Creates a cache entry with explicitly supplied timestamps.
    ///
    /// This initializer is useful when reconstructing an entry loaded from persistent storage.
    /// The access count begins at zero.
    ///
    /// - Parameters:
    ///   - key: The unique key identifying the value.
    ///   - value: The value to store.
    ///   - creation: The date when the entry was originally created.
    ///   - lastAccess: The date when the entry was most recently accessed.
    public init(key: KeyType, value: CachedType, creation: Date, lastAccess: Date) {
        self.key = key
        self.value = value
        self.creation = creation
        self.lastAccess = lastAccess
    }

    /// Records an access at a date.
    mutating func updateLastAccess(at date: Date) {
        lastAccess = date
        if accessCount < .max {
            accessCount += 1
        }
    }
}
