import Foundation
@testable import SwiftStash
import Testing

@Suite(.serialized) struct JsonDiskStorageSerializerTests {

    private struct TestCodable: Codable, Equatable {
        let name: String
        let value: Int
    }

    @Test func serializeAndDeserialize() throws {
        let serializer = JsonDiskStorageSerializer<TestCodable>()
        let original = TestCodable(name: "test", value: 42)

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeString() throws {
        let serializer = JsonDiskStorageSerializer<String>()
        let original = "Hello, World!"

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func serializeArray() throws {
        let serializer = JsonDiskStorageSerializer<[Int]>()
        let original = [1, 2, 3, 4, 5]

        let data = try serializer.serialize(original)
        let deserialized = try serializer.deserialize(data)

        #expect(deserialized == original)
    }

    @Test func deserializeInvalidDataReturnsNil() throws {
        let serializer = JsonDiskStorageSerializer<TestCodable>()
        let invalidData = Data("not json".utf8)

        #expect(throws: Error.self) {
            _ = try serializer.deserialize(invalidData)
        }
    }
}
