import Foundation

/// Defines the persistence operations used by a cache.
///
/// A storage engine loads entries, persists individual entries, removes individual
/// entries, and clears its contents. Implementations define their own error-handling
/// behavior; this protocol does not require operations to throw.
public protocol StorageEngine {

    /// The key type used to identify stored values.
    associatedtype KeyType: CacheKey

    /// The cache value type stored by this engine.
    associatedtype StoredType: Sendable

    /// Loads the entries currently available from storage.
    ///
    /// - Returns: The entries loaded by the implementation. The order is implementation-defined.
    @discardableResult func load() -> [CacheEntry<KeyType, StoredType>]

    /// Removes an entry from storage.
    ///
    /// - Parameter entry: The entry whose stored representation should be removed.
    func delete(_ entry: CacheEntry<KeyType, StoredType>)

    /// Persists an entry to storage.
    ///
    /// - Parameter entry: The entry to persist.
    /// - Returns: `true` when the implementation reports that persistence succeeded;
    ///   otherwise, `false`.
    @discardableResult func persist(_ entry: CacheEntry<KeyType, StoredType>) -> Bool

    /// Removes all entries managed by the storage engine.
    func clear()

    /// Loads the metadata of the stored entries without their values.
    ///
    /// Implement this method, ``loadValue(for:)``, and ``delete(forKey:)`` to let a cache
    /// load values on demand instead of reading every value when it's created.
    ///
    /// - Returns: The metadata of the stored entries, or `nil` when the engine loads
    ///   values only through ``load()``. The default implementation returns `nil`.
    func loadMetadata() -> [CacheEntryMetadata<KeyType>]?

    /// Loads the value stored for a key.
    ///
    /// A cache calls this method only when ``loadMetadata()`` returns a non-`nil` value.
    ///
    /// - Parameter key: The key of the entry whose value to load.
    /// - Returns: The stored value, or `nil` when it's missing or can't be read.
    ///   The default implementation returns `nil`.
    func loadValue(for key: KeyType) -> StoredType?

    /// Removes the entry for a key from storage.
    ///
    /// A cache calls this method instead of ``delete(_:)`` to remove an entry whose value
    /// it hasn't loaded. The default implementation does nothing.
    ///
    /// - Parameter key: The key of the entry to remove.
    func delete(forKey key: KeyType)

    /// Persists an entry's updated metadata, such as its last-access date, without rewriting its value.
    ///
    /// With the LRU policy, a cache calls this method after each read. When it returns `false`,
    /// the cache persists the whole entry with ``persist(_:)`` instead.
    ///
    /// - Parameter metadata: The updated metadata of a stored entry.
    /// - Returns: `true` when the metadata was persisted; `false` when the engine can't persist
    ///   metadata alone or the write failed. The default implementation returns `false`.
    @discardableResult func persistMetadata(_ metadata: CacheEntryMetadata<KeyType>) -> Bool
}

public extension StorageEngine {

    /// Returns `nil`, so caches load values through ``load()``.
    func loadMetadata() -> [CacheEntryMetadata<KeyType>]? {
        nil
    }

    /// Returns `nil`.
    func loadValue(for _: KeyType) -> StoredType? {
        nil
    }

    /// Does nothing.
    func delete(forKey _: KeyType) {}

    /// Returns `false`, so caches persist whole entries.
    func persistMetadata(_: CacheEntryMetadata<KeyType>) -> Bool {
        false
    }
}
