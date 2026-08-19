import Foundation

#if canImport(Kronos)
private import Kronos
#endif

/// A shared wall clock that uses NTP time when available and supports a fixed,
/// manually advanced date for deterministic tests.
///
/// On platforms where Kronos is available, the clock returns its synchronized
/// time after synchronization succeeds and otherwise falls back to the system
/// date. Calling ``reset(year:month:day:hour:minute:second:)`` or
/// ``set(unixTimestamp:)`` switches the clock to a controlled date.
public final class MonotonicClock: @unchecked Sendable {
    private static let productionInstance = MonotonicClock()

    /// The process-wide clock used by ``Date/monotonic``.
    public static var shared: MonotonicClock {
        productionInstance
    }

    private let lock = NSLock()
    private var controlledDate: Date?

    /// The controlled date, synchronized NTP date, or current system date.
    ///
    /// A controlled date takes precedence over all other time sources.
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
    /// This method has no effect on platforms where Kronos isn't available or
    /// after a controlled date has been set.
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
    @discardableResult public func tick(seconds value: Int) -> Date {
        tick(TimeInterval(value))
    }

    /// Advances the controlled date by a number of minutes.
    ///
    /// - Parameter value: The number of minutes to add.
    /// - Returns: The result of advancing the clock.
    @discardableResult public func tick(minutes value: Int) -> Date {
        tick(seconds: 60 * value)
    }

    /// Advances the controlled date by a number of hours.
    ///
    /// - Parameter value: The number of hours to add.
    /// - Returns: The result of advancing the clock.
    @discardableResult public func tick(hours value: Int) -> Date {
        tick(minutes: 60 * value)
    }

    /// Advances the controlled date by a number of days.
    ///
    /// - Parameter value: The number of 24-hour periods to add.
    /// - Returns: The result of advancing the clock.
    @discardableResult public func tick(days value: Int) -> Date {
        tick(hours: 24 * value)
    }

    /// Advances the controlled date by a number of weeks.
    ///
    /// - Parameter value: The number of seven-day periods to add.
    /// - Returns: The result of advancing the clock.
    @discardableResult public func tick(weeks value: Int) -> Date {
        tick(days: 7 * value)
    }

    /// Sets the controlled date from a Unix timestamp.
    ///
    /// - Parameter unixTimestamp: The number of seconds since January 1, 1970,
    ///   at 00:00:00 UTC.
    /// - Returns: The new controlled date.
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

public extension Date {
    /// The date reported by ``MonotonicClock/shared``.
    static var monotonic: Date {
        MonotonicClock.shared.now
    }

    /// The interval from the shared clock's current date to this date.
    ///
    /// A positive value means this date is later than ``monotonic``.
    var timeIntervalSinceMonotonic: TimeInterval {
        timeIntervalSince(.monotonic)
    }
}
