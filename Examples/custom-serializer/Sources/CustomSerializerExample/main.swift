import Foundation
import SwiftStash

private struct Temperature: Equatable, Sendable {
    let celsius: Double
}

private struct TemperatureSerializer: DiskStorageSerializer {
    func serialize(_ value: Temperature) throws -> Data {
        withUnsafeBytes(of: value.celsius.bitPattern.bigEndian) { Data($0) }
    }

    func deserialize(_ data: Data) throws -> Temperature? {
        guard data.count == MemoryLayout<UInt64>.size else {
            return nil
        }

        var bits: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &bits) { data.copyBytes(to: $0) }
        return Temperature(celsius: Double(bitPattern: UInt64(bigEndian: bits)))
    }
}

@main private enum CustomSerializerExample {
    static func main() async throws {
        let directoryName = "temperature-example"

        let storage = DiskStorageEngine(
            directory: directoryName,
            serializer: TemperatureSerializer()
        )
        let cache = await Cache(storagePolicy: storage)

        await cache.add(Temperature(celsius: 21.5), for: "office")

        if let temperature = await cache["office"] {
            print("Office: \(temperature.celsius) °C")
        }
    }
}
