import Foundation

/// A type that converts cache values to and from their on-disk representation.
///
/// Conform to this protocol to store a custom value type with ``DiskStorageEngine``.
/// Implementations may throw when conversion fails or return `nil` from
/// ``deserialize(_:)`` when data cannot be converted to a value.
///
/// Example:
/// ```swift
/// struct MyTypeSerializer: DiskStorageSerializer {
///     func serialize(_ value: MyType) throws -> Data { ... }
///     func deserialize(_ data: Data) throws -> MyType? { ... }
/// }
/// ```
public protocol DiskStorageSerializer {

    /// The value type this serializer converts.
    associatedtype SerializedType

    /// Converts a value into the data stored on disk.
    ///
    /// - Parameter value: The value to serialize.
    /// - Returns: The serialized data.
    /// - Throws: An error encountered while serializing `value`.
    func serialize(_ value: SerializedType) throws -> Data

    /// Converts data read from disk into a value.
    ///
    /// - Parameter data: The serialized data to deserialize.
    /// - Returns: The deserialized value, or `nil` when this serializer cannot
    ///   produce a value without throwing.
    /// - Throws: An error encountered while deserializing `data`.
    func deserialize(_ data: Data) throws -> SerializedType?

}
