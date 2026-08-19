import Foundation

/// A no-op implementation of ``StorageEngine``.
///
/// This engine does not retain entries: ``load()`` always returns an empty array,
/// ``persist(_:)`` always succeeds, and ``delete(_:)`` and ``clear()`` have no effect.
/// It is useful where a cache needs no backing storage, such as tests.
///
/// Example:
/// ```swift
/// let engine = MemoryStorageEngine<MyType>()
/// ```
public class MemoryStorageEngine<StoredType: CacheableDataType>: StorageEngine {

    /// Creates a no-op storage engine.
    public init() {}

    /// Returns no entries.
    ///
    /// - Returns: An empty array.
    @discardableResult public func load() -> [CacheEntry<StoredType>] {
        []
    }

    /// Does nothing.
    ///
    /// - Parameter entry: Ignored.
    public func delete(_: CacheEntry<StoredType>) {}

    /// Does nothing and reports success.
    ///
    /// - Parameter entry: Ignored.
    /// - Returns: Always `true`.
    @discardableResult public func persist(_: CacheEntry<StoredType>) -> Bool {
        true
    }

    /// Does nothing.
    public func clear() {}

}
