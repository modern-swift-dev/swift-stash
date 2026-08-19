import Foundation
@testable import SwiftStash
import Testing

@Suite(.serialized) struct StringDiskStorageSerializerTests {

    @Test func serializeAndDeserializeUTF8() throws {
        let serializer = StringDiskStorageSerializer<NSString>()
        let original = "Hello, World!"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeAndDeserializeUnicode() throws {
        let serializer = StringDiskStorageSerializer<NSString>()
        let original = "Hello, 世界! 🌍"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeEmptyString() throws {
        let serializer = StringDiskStorageSerializer<NSString>()
        let original = ""

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func deserializeWithDifferentEncoding() throws {
        let serializer = StringDiskStorageSerializer<NSString>(encoding: .ascii)
        let original = "Hello"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }
}
