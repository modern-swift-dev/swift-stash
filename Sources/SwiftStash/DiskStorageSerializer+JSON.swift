import Foundation

/// A JSON-backed serializer for `Codable` values.
///
/// The supplied encoder and decoder determine the JSON representation and decoding
/// strategies used by this serializer.
///
/// Example:
/// ```swift
/// let serializer = JsonDiskStorageSerializer<MyCodableType>()
/// ```
public class JsonDiskStorageSerializer<SerializedType: Codable>: DiskStorageSerializer {

    /// The JSON Encoder
    private let encoder: JSONEncoder

    /// The JSON Decoder
    private let decoder: JSONDecoder

    /// Creates a JSON serializer with the specified encoder and decoder.
    ///
    /// - Parameters:
    ///   - encoder: The encoder used to serialize values. The default is a new
    ///     ``JSONEncoder``.
    ///   - decoder: The decoder used to deserialize data. The default is a new
    ///     ``JSONDecoder``.
    public init(encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.encoder = encoder
        self.decoder = decoder
    }

    /// Encodes a value as JSON data.
    ///
    /// - Parameter value: The `Codable` value to encode.
    /// - Returns: JSON data produced by this serializer's encoder.
    /// - Throws: An error from the configured encoder when it cannot encode `value`.
    public func serialize(_ value: SerializedType) throws -> Data {
        try encoder.encode(value)
    }

    /// Decodes JSON data into a value.
    ///
    /// - Parameter data: The JSON data to decode.
    /// - Returns: The decoded value.
    /// - Throws: An error from the configured decoder when `data` is not valid JSON
    ///   for `SerializedType`.
    public func deserialize(_ data: Data) throws -> SerializedType? {
        try decoder.decode(SerializedType.self, from: data)
    }
}
