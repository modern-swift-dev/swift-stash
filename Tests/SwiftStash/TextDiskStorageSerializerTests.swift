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

        #expect(throws: TextDiskStorageSerializerError.unrepresentableValue(encoding: .ascii)) {
            try serializer.serialize("🌍")
        }
    }
}
