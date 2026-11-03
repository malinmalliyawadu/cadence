import Foundation

/// How long to rest before a set. Heavy multi-joint work needs the longest for strength to
/// come back (Schoenfeld 2016: three minutes beat one for compound lifts), single-joint pump
/// work the least. The planner's session minutes use the same numbers, so the clock in the gym
/// and the load model agree.
public enum RestInterval {
    public static func seconds(for role: ExerciseRole, repRange: ClosedRange<Int>) -> Double {
        let heavy = repRange.upperBound <= 6
        let pump = repRange.lowerBound >= 15
        switch role {
        case .compound: return heavy ? 180 : 150
        case .accessory: return heavy ? 135 : 105
        case .isolation: return pump ? 60 : 75
        }
    }
}

/// A countdown between sets. It is a span of wall-clock time rather than a ticking counter,
/// so it survives the app being suspended and reads the same in the app, the Live Activity
/// and the notification.
public struct RestTimer: Codable, Sendable, Hashable {
    public let startedAt: Date
    public private(set) var endsAt: Date

    public init(startedAt: Date = .now, seconds: Double) {
        self.startedAt = startedAt
        endsAt = startedAt.addingTimeInterval(max(0, seconds))
    }

    public var duration: TimeInterval { endsAt.timeIntervalSince(startedAt) }

    public func remaining(at date: Date = .now) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(date))
    }

    public func isOver(at date: Date = .now) -> Bool { date >= endsAt }

    /// Seconds past the end, zero while resting.
    public func overtime(at date: Date = .now) -> TimeInterval {
        max(0, date.timeIntervalSince(endsAt))
    }

    /// Fraction of the rest already taken, 0 ... 1.
    public func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(startedAt) / duration))
    }

    /// More or less rest. Adding after the end counts from now, since the time already past
    /// was spent anyway; taking away never ends the rest before now.
    public func adjusted(by seconds: Double, at date: Date = .now) -> RestTimer {
        var copy = self
        let base = seconds > 0 ? max(endsAt, date) : endsAt
        copy.endsAt = max(date, base.addingTimeInterval(seconds))
        return copy
    }
}
