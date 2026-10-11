import Foundation

/// A source of the current date for a ``Cache``.
///
/// The cache uses its clock to timestamp new entries and accesses, and to decide
/// which entries have expired. Use ``NetworkTimeClock`` in production and
/// ``ManualClock`` in tests.
public protocol CacheClock: Sendable {

    /// The current date.
    var now: Date { get }
}

/// A clock whose date changes only when you set or advance it.
///
/// Pass a manual clock to a ``Cache`` to test expiration and eviction without waiting
/// for real time to pass. Each instance is independent, so tests using separate
/// clocks can run in parallel.
///
/// Example:
/// ```swift
/// let clock = ManualClock()
/// let cache = Cache(policy: .fifo(threshold: 60), storageEngine: storage, clock: clock)
/// await cache.add("value", for: "key")
/// clock.advance(by: 60)
/// await cache.evictExpired()
/// ```
public final class ManualClock: CacheClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    /// Creates a clock set to a date.
    ///
    /// - Parameter now: The clock's initial date. The default is the current system date.
    public init(now: Date = Date()) {
        date = now
    }

    /// The clock's current date.
    public var now: Date {
        lock.withLock { date }
    }

    /// Moves the clock by a time interval.
    ///
    /// - Parameter interval: The number of seconds to move. A negative value moves the clock backward.
    public func advance(by interval: TimeInterval) {
        lock.withLock { date.addTimeInterval(interval) }
    }

    /// Sets the clock to a date.
    ///
    /// - Parameter newDate: The clock's new date.
    public func set(_ newDate: Date) {
        lock.withLock { date = newDate }
    }
}
