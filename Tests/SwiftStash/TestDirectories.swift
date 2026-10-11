import Foundation
@testable import SwiftStash

/// Hands out uniquely named disk-storage directories and removes them when released.
///
/// Store one in a suite property: each test gets a new suite instance, so the
/// directories are removed when the test finishes.
final class TestDirectories: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    /// Returns a unique directory name below the cache root, starting with a prefix.
    func make(_ prefix: String) -> String {
        let name = "\(prefix)_\(UUID().uuidString)"
        lock.withLock { names.append(name) }
        return name
    }

    deinit {
        for name in names {
            try? FileManager.default.removeItem(at: URL.swiftStashCacheDirectory.appendingPathComponent(name))
        }
    }
}
