import Foundation

/// Errors produced when serializing a string with a configured encoding.
public enum TextDiskStorageSerializerError: Error, Equatable {
    /// The string contains characters that the encoding cannot represent.
    case unrepresentableValue(encoding: String.Encoding)
}

/// A text-backed serializer for `String` values.
///
/// Values are converted with the encoding supplied at initialization.
///
/// Example:
/// ```swift
/// let engine = DiskStorageEngine(
///     directory: "notes",
///     serializer: TextDiskStorageSerializer(encoding: .utf8)
/// )
/// ```
public struct TextDiskStorageSerializer: DiskStorageSerializer, Sendable {

    /// The Encoding
    private let encoding: String.Encoding

    /// Creates a string serializer with the specified character encoding.
    ///
    /// - Parameter encoding: The encoding used to convert strings to and from data.
    ///   The default is `.utf8`.
    public init(encoding: String.Encoding = .utf8) {
        self.encoding = encoding
    }

    /// Converts a string to data using this serializer's encoding.
    ///
    /// - Parameter value: The string to serialize.
    /// - Returns: The encoded data.
    /// - Throws: ``TextDiskStorageSerializerError/unrepresentableValue(encoding:)``
    ///   when the value cannot be represented in the configured encoding.
    public func serialize(_ value: String) throws -> Data {
        guard let data = value.data(using: encoding) else {
            throw TextDiskStorageSerializerError.unrepresentableValue(encoding: encoding)
        }
        return data
    }

    /// Converts encoded data to a string using this serializer's encoding.
    ///
    /// - Parameter data: The encoded string data to deserialize.
    /// - Returns: The decoded string, or `nil` when `data` cannot be decoded with
    ///   the configured encoding.
    /// - Throws: This implementation does not throw.
    public func deserialize(_ data: Data) throws -> String? {
        String(data: data, encoding: encoding)
    }
}
