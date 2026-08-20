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
    associatedtype StoredType: CacheableDataType

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
}
