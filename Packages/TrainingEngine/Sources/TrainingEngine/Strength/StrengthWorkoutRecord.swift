import Foundation

/// What a finished lifting session looks like as a workout in Apple Health: when it ran and
/// the active energy it burned. There is no start button, so the span comes from the sets.
public enum StrengthWorkoutRecord {
    /// From the start of the first logged set to the end of the last. Sets logged after the
    /// fact land within a minute or two of each other; when the logged span covers less than
    /// half the planned time, the session is taken to have run for the planned minutes and
    /// ended with the last set.
    /// - Parameters:
    ///   - setTimes: when each set was logged, in any order.
    ///   - firstSetSeconds: how long the first set itself took, since it is logged at its end.
    public static func interval(setTimes: [Date], firstSetSeconds: Double, plannedMinutes: Double) -> DateInterval? {
        guard let first = setTimes.min(), let last = setTimes.max() else { return nil }
        let logged = DateInterval(start: first.addingTimeInterval(-max(0, firstSetSeconds)), end: last)
        let planned = max(0, plannedMinutes) * 60
        if logged.duration < planned / 2 {
            return DateInterval(start: last.addingTimeInterval(-planned), end: last)
        }
        return logged
    }

    /// Metabolic equivalent for resistance training at a session RPE, from the Compendium of
    /// Physical Activities: 3.5 for moderate circuit-style work up to 6 for vigorous lifting.
    public static func met(rpe: Double) -> Double {
        let fraction = min(1, max(0, (rpe - 5) / 3))
        return 3.5 + fraction * 2.5
    }

    /// Active kilocalories: energy above rest, which is one MET, as Health counts it.
    public static func activeKilocalories(bodyweightKg: Double, minutes: Double, rpe: Double) -> Double {
        (met(rpe: rpe) - 1) * max(0, bodyweightKg) * max(0, minutes) / 60
    }

    /// How long a session the watch recorded waits for the watch's workout before Cadence saves
    /// its own estimate. The watch hands its workouts to the phone's Health store when it gets
    /// round to it, which can be minutes after the session ends, or longer when the phone is out
    /// of reach. Saving early puts the session in Fitness twice until the watch's copy replaces it.
    public static let watchWorkoutGrace: TimeInterval = 3 * 60 * 60

    /// Whether Cadence should save its own estimate of a finished session now. A session nothing
    /// recorded is saved as soon as it finishes; one the watch recorded is saved by the watch, so
    /// only once its workout is overdue (it never arrived: the watch could not start or save it).
    public static func estimateIsDue(recordedLive: Bool, completedAt: Date, now: Date) -> Bool {
        !recordedLive || now.timeIntervalSince(completedAt) >= watchWorkoutGrace
    }
}
