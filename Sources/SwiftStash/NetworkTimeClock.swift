import Foundation

#if canImport(Kronos)
    private import Kronos
#endif

/// A shared wall clock that uses NTP time when available.
///
/// This is the default clock of a ``Cache``. On platforms where Kronos is available,
/// the clock returns its synchronized time after synchronization succeeds and
/// otherwise falls back to the system date. It is a wall clock, so its time can
/// move backward when the system date or the synchronized time changes.
///
/// To control time in tests, pass a ``ManualClock`` to the cache instead.
public final class NetworkTimeClock: CacheClock, Sendable {

    /// The process-wide clock used by caches that don't specify one.
    public static let shared = NetworkTimeClock()

    private init() {}

    /// The synchronized NTP date, or the current system date.
    public var now: Date {
        #if canImport(Kronos)
            return Clock.now ?? Date()
        #else
            return Date()
        #endif
    }

    /// Starts NTP synchronization.
    ///
    /// The clock uses the system date until you call this method and synchronization
    /// succeeds. Call it once early in your app's lifetime. Synchronization queries NTP
    /// servers in the background and returns immediately.
    ///
    /// This method has no effect on platforms where Kronos isn't available (watchOS,
    /// visionOS, and Linux).
    public func synchronize() {
        #if canImport(Kronos)
            Clock.sync()
        #endif
    }
}
