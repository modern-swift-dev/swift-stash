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
public final class NetworkTimeClock: CacheClock, @unchecked Sendable {
    private static let productionInstance = NetworkTimeClock()

    /// The process-wide clock used by caches that don't specify one.
    public static var shared: NetworkTimeClock {
        productionInstance
    }

    private let lock = NSLock()
    private var controlledDate: Date?

    /// The synchronized NTP date, or the current system date.
    ///
    /// A controlled date set by the deprecated test methods takes precedence over all other time sources.
    public var now: Date {
        if let controlledDate = lock.withLock({ controlledDate }) {
            return controlledDate
        }

        #if canImport(Kronos)
            return Clock.now ?? Date()
        #else
            return Date()
        #endif
    }

    /// Starts NTP synchronization when the clock isn't using a controlled date.
    ///
    /// The clock uses the system date until you call this method and synchronization
    /// succeeds. Call it once early in your app's lifetime. Synchronization queries NTP
    /// servers in the background and returns immediately.
    ///
    /// This method has no effect on platforms where Kronos isn't available (watchOS,
    /// visionOS, and Linux) or after a controlled date has been set.
    public func synchronize() {
        guard lock.withLock({ controlledDate == nil }) else {
            return
        }
        #if canImport(Kronos)
            Clock.sync()
        #endif
    }

    /// Advances the controlled date by a time interval.
    ///
    /// If the clock doesn't have a controlled date, this method leaves the
    /// clock unchanged and returns the current system date.
    ///
    /// - Parameter value: The number of seconds to add. A negative value moves
    ///   the controlled date backward.
    /// - Returns: The updated controlled date, or the current system date when
    ///   the clock isn't controlled.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func tick(_ value: TimeInterval) -> Date {
        lock.withLock {
            guard let date = controlledDate else {
                return Date()
            }
            let updatedDate = date.addingTimeInterval(value)
            controlledDate = updatedDate
            return updatedDate
        }
    }

    /// Advances the controlled date by a number of seconds.
    ///
    /// - Parameter value: The number of seconds to add.
    /// - Returns: The result of advancing the clock.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func tick(seconds value: Int) -> Date {
        tick(TimeInterval(value))
    }

    /// Advances the controlled date by a number of minutes.
    ///
    /// - Parameter value: The number of minutes to add.
    /// - Returns: The result of advancing the clock.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func tick(minutes value: Int) -> Date {
        tick(seconds: 60 * value)
    }

    /// Advances the controlled date by a number of hours.
    ///
    /// - Parameter value: The number of hours to add.
    /// - Returns: The result of advancing the clock.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func tick(hours value: Int) -> Date {
        tick(minutes: 60 * value)
    }

    /// Advances the controlled date by a number of days.
    ///
    /// - Parameter value: The number of 24-hour periods to add.
    /// - Returns: The result of advancing the clock.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func tick(days value: Int) -> Date {
        tick(hours: 24 * value)
    }

    /// Advances the controlled date by a number of weeks.
    ///
    /// - Parameter value: The number of seven-day periods to add.
    /// - Returns: The result of advancing the clock.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func tick(weeks value: Int) -> Date {
        tick(days: 7 * value)
    }

    /// Sets the controlled date from a Unix timestamp.
    ///
    /// - Parameter unixTimestamp: The number of seconds since January 1, 1970,
    ///   at 00:00:00 UTC.
    /// - Returns: The new controlled date.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    @discardableResult public func set(unixTimestamp: TimeInterval) -> Date {
        lock.withLock {
            let date = Date(timeIntervalSince1970: unixTimestamp)
            controlledDate = date
            return date
        }
    }

    /// Sets the controlled date from components in the current calendar and
    /// time zone.
    ///
    /// If the components don't form a valid date, the controlled date is set
    /// to the current system date.
    ///
    /// - Parameters:
    ///   - year: The year component.
    ///   - month: The month component. The default is `1`.
    ///   - day: The day component. The default is `1`.
    ///   - hour: The hour component. The default is `0`.
    ///   - minute: The minute component. The default is `0`.
    ///   - second: The second component. The default is `0`.
    @available(*, deprecated, message: "Pass a ManualClock to Cache instead.")
    public func reset(
        year: Int,
        month: Int = 1,
        day: Int = 1,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) {
        let components = DateComponents(
            calendar: .current,
            timeZone: .current,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        lock.withLock {
            controlledDate = Calendar.current.date(from: components) ?? Date()
        }
    }
}

/// The previous name of ``NetworkTimeClock``.
@available(*, deprecated, renamed: "NetworkTimeClock")
public typealias MonotonicClock = NetworkTimeClock

public extension Date {
    /// The date reported by ``NetworkTimeClock/shared``.
    @available(*, deprecated, message: "Use NetworkTimeClock.shared.now.")
    static var monotonic: Date {
        NetworkTimeClock.shared.now
    }

    /// The interval from the shared clock's current date to this date.
    ///
    /// A positive value means this date is later than ``NetworkTimeClock/shared``'s current date.
    @available(*, deprecated, message: "Use timeIntervalSince(NetworkTimeClock.shared.now).")
    var timeIntervalSinceMonotonic: TimeInterval {
        timeIntervalSince(NetworkTimeClock.shared.now)
    }
}
