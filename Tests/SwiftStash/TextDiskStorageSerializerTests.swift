import Foundation
@testable import SwiftStash
import Testing

@Suite(.serialized) struct TextDiskStorageSerializerTests {

    @Test func serializeAndDeserializeUTF8() throws {
        let serializer = TextDiskStorageSerializer()
        let original = "Hello, World!"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeAndDeserializeUnicode() throws {
        let serializer = TextDiskStorageSerializer()
        let original = "Hello, 世界! 🌍"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeEmptyString() throws {
        let serializer = TextDiskStorageSerializer()
        let original = ""

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func deserializeWithDifferentEncoding() throws {
        let serializer = TextDiskStorageSerializer(encoding: .ascii)
        let original = "Hello"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeUnrepresentableCharactersThrows() {
        let serializer = TextDiskStorageSerializer(encoding: .ascii)

        #expect(throws: StringDiskStorageSerializerError.unrepresentableValue(encoding: .ascii)) {
            try serializer.serialize("🌍")
        }
    }
}

/// Calls the deprecated serializer through a protocol so the tests compile without deprecation warnings.
private protocol DeprecatedStringSerializer {
    func roundTrip(_ value: String, encoding: String.Encoding) throws -> String?
}

private struct DeprecatedStringSerializerCalls: DeprecatedStringSerializer {
    @available(*, deprecated)
    func roundTrip(_ value: String, encoding: String.Encoding) throws -> String? {
        let serializer = StringDiskStorageSerializer<NSString>(encoding: encoding)
        return try serializer.deserialize(serializer.serialize(value))
    }
}

struct DeprecatedStringDiskStorageSerializerTests {
    private let deprecated: any DeprecatedStringSerializer = DeprecatedStringSerializerCalls()

    @Test func roundTripsThroughTheReplacement() throws {
        #expect(try deprecated.roundTrip("Hello, 世界! 🌍", encoding: .utf8) == "Hello, 世界! 🌍")
    }

    @Test func reportsUnrepresentableValues() {
        #expect(throws: StringDiskStorageSerializerError.unrepresentableValue(encoding: .ascii)) {
            try deprecated.roundTrip("🌍", encoding: .ascii)
        }
    }
}
