/// A key that can identify values in a ``Cache``.
///
/// Cache keys must have a lossless string representation so storage engines can
/// persist and restore them. String-backed enums receive default implementations.
public protocol CacheKey: Hashable, Sendable {

    /// The string representation used by persistent storage.
    var stringValue: String { get }

    /// Restores a key from its persisted string representation.
    ///
    /// - Parameter stringValue: The representation previously returned by ``stringValue``.
    init?(stringValue: String)
}

public extension CacheKey where Self: RawRepresentable, RawValue == String {

    /// The key's raw string value.
    var stringValue: String {
        rawValue
    }

    /// Restores a key from a raw string value.
    ///
    /// - Parameter stringValue: A raw value supported by this type.
    init?(stringValue: String) {
        self.init(rawValue: stringValue)
    }
}

extension String: CacheKey {

    public var stringValue: String {
        self
    }

    public init?(stringValue: String) {
        self = stringValue
    }
}
