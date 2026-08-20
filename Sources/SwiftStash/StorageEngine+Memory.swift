import Foundation

/// A no-op implementation of ``StorageEngine``.
///
/// This engine does not retain entries: ``load()`` always returns an empty array,
/// ``persist(_:)`` always succeeds, and ``delete(_:)`` and ``clear()`` have no effect.
/// It is useful where a cache needs no backing storage, such as tests.
///
/// Example:
/// ```swift
/// let engine = MemoryStorageEngine<MyKey, MyType>()
/// ```
public class MemoryStorageEngine<KeyType: CacheKey, StoredType: CacheableDataType>: StorageEngine {

    /// Creates a no-op storage engine.
    public init() {}

    /// Returns no entries.
    ///
    /// - Returns: An empty array.
    @discardableResult public func load() -> [CacheEntry<KeyType, StoredType>] {
        []
    }

    /// Does nothing.
    ///
    /// - Parameter entry: Ignored.
    public func delete(_: CacheEntry<KeyType, StoredType>) {}

    /// Does nothing and reports success.
    ///
    /// - Parameter entry: Ignored.
    /// - Returns: Always `true`.
    @discardableResult public func persist(_: CacheEntry<KeyType, StoredType>) -> Bool {
        true
    }

    /// Does nothing.
    public func clear() {}

}
