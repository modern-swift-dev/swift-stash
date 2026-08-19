import Foundation

/// A text-backed serializer for `String` values.
///
/// Values are converted with the encoding supplied at initialization. Use
/// `StringDiskStorageSerializer<NSString>` when supplying this serializer to a
/// ``DiskStorageEngine`` that stores strings.
///
/// Example:
/// ```swift
/// let serializer = StringDiskStorageSerializer<NSString>(encoding: .utf8)
/// ```
public class StringDiskStorageSerializer<SerializedType: NSString>: DiskStorageSerializer {

    /// The Encoding
    private let encoding: String.Encoding

    /// Creates a string serializer with the specified character encoding.
    ///
    /// - Parameter encoding: The encoding used to convert strings to and from data.
    ///   The default is ``String/Encoding/utf8``.
    public init(encoding: String.Encoding = .utf8) {
        self.encoding = encoding
    }

    /// Converts a string to data using this serializer's encoding.
    ///
    /// - Important: `value` must be representable in the configured encoding.
    ///   Otherwise, the underlying conversion returns `nil` and this implementation
    ///   traps while unwrapping that result.
    /// - Parameter value: The string to serialize.
    /// - Returns: The encoded data.
    /// - Throws: This implementation does not throw.
    public func serialize(_ value: String) throws -> Data {
        // swiftlint:disable:next force_unwrapping
        value.data(using: encoding)!
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
