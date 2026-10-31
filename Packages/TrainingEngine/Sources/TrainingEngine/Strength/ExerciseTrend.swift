import Foundation

/// One session on one movement, as its trend reads it.
public struct ExerciseTrendPoint: Sendable, Hashable {
    public let date: Date
    /// Estimated one-rep max from the session's rated sets, as progression reads it. Bodyweight
    /// movements include bodyweight, so dips at no added load still have a strength to track.
    public let oneRepMax: Double
    /// The heaviest working set, and of those the one with the most reps. Its weight is as
    /// logged: added load for bodyweight movements.
    public let topSet: PerformedSet
    /// Load times reps across the working sets, bodyweight included for bodyweight movements.
    public let volumeKg: Double
    public let workingSets: Int
    /// Whether the estimated max beat every earlier session's. The first session sets none.
    public let isBest: Bool

    public func value(of metric: TrendMetric) -> Double {
        switch metric {
        case .oneRepMax: oneRepMax
        case .topSet: topSet.weightKg
        case .volume: volumeKg
        }
    }
}

/// What a movement's trend can follow.
public enum TrendMetric: String, CaseIterable, Sendable, Hashable {
    /// Strength, whatever the reps: the number progression works from.
    case oneRepMax
    /// The heaviest weight lifted for working reps.
    case topSet
    /// Work done in the session, which grows with sets and reps as well as load.
    case volume
}

public enum TrendDirection: String, Sendable, Hashable {
    case climbing, holding, slipping
}

/// A metric across a window: where it started and ended, and which way it is heading.
public struct ExerciseTrendSummary: Sendable, Hashable {
    public let first: ExerciseTrendPoint
    public let latest: ExerciseTrendPoint
    public let sessions: Int
    /// Least-squares slope over the window, per week. `nil` under three sessions.
    public let perWeek: Double?
    /// From the slope against the window's mean. `nil` under three sessions.
    public let direction: TrendDirection?
    let metric: TrendMetric

    public var change: Double { latest.value(of: metric) - first.value(of: metric) }
    public var changeFraction: Double {
        let start = first.value(of: metric)
        return start > 0 ? change / start : 0
    }
}

/// The sessions that set each record.
public struct ExerciseRecords: Sendable, Hashable {
    public let bestOneRepMax: ExerciseTrendPoint?
    public let heaviestSet: ExerciseTrendPoint?
    public let mostVolume: ExerciseTrendPoint?
}

/// How a movement has gone over time, from the same history progression reads.
public enum ExerciseTrend {
    /// A slope of half a percent of the mean a week is a trend; less is noise in RIR and reps.
    public static let directionThreshold = 0.005

    /// One point per logged session on `exercise`, oldest first. `bodyweightKg` is today's, so a
    /// bodyweight movement's history is read at today's bodyweight, as progression reads it.
    public static func points(for exercise: Exercise, history: [ExerciseHistoryEntry], bodyweightKg: Double = 0) -> [ExerciseTrendPoint] {
        let base = exercise.equipment == .bodyweight ? max(0, bodyweightKg) : 0
        var best: Double?
        return history
            .filter { $0.exerciseID == exercise.id }
            .sorted { $0.date < $1.date }
            .compactMap { entry in
                let working = entry.workingSets
                guard let top = working.max(by: { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }),
                      let oneRepMax = entry.sessionOneRepMax(bodyweightKg: base) else { return nil }
                let isBest = best.map { oneRepMax > $0 } ?? false
                best = max(best ?? oneRepMax, oneRepMax)
                return ExerciseTrendPoint(
                    date: entry.date,
                    oneRepMax: oneRepMax,
                    topSet: top,
                    volumeKg: working.map { ($0.weightKg + base) * Double($0.reps) }.reduce(0, +),
                    workingSets: working.count,
                    isBest: isBest
                )
            }
    }

    /// The trend of `metric` over the points on or after `since`. `nil` under two sessions.
    public static func summary(of points: [ExerciseTrendPoint], metric: TrendMetric, since: Date? = nil) -> ExerciseTrendSummary? {
        let window = since.map { start in points.filter { $0.date >= start } } ?? points
        guard let first = window.first, let latest = window.last, window.count >= 2 else { return nil }
        let perWeek = window.count >= 3 ? slopePerWeek(window, metric: metric) : nil
        let mean = window.map { $0.value(of: metric) }.reduce(0, +) / Double(window.count)
        let direction = perWeek.map { slope -> TrendDirection in
            guard mean > 0 else { return .holding }
            let relative = slope / mean
            if relative >= directionThreshold { return .climbing }
            if relative <= -directionThreshold { return .slipping }
            return .holding
        }
        return ExerciseTrendSummary(first: first, latest: latest, sessions: window.count, perWeek: perWeek, direction: direction, metric: metric)
    }

    public static func records(of points: [ExerciseTrendPoint]) -> ExerciseRecords {
        // Ties go to the earliest session: a record is set once and only beaten by more.
        func best(_ value: (ExerciseTrendPoint) -> Double) -> ExerciseTrendPoint? {
            points.reduce(nil) { current, point in
                guard let current else { return point }
                return value(point) > value(current) ? point : current
            }
        }
        return ExerciseRecords(
            bestOneRepMax: best(\.oneRepMax),
            heaviestSet: points.reduce(nil) { current, point in
                guard let current else { return point }
                return (point.topSet.weightKg, point.topSet.reps) > (current.topSet.weightKg, current.topSet.reps) ? point : current
            },
            mostVolume: best(\.volumeKg)
        )
    }

    private static func slopePerWeek(_ points: [ExerciseTrendPoint], metric: TrendMetric) -> Double? {
        guard let origin = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(origin) / (7 * 86_400) }
        let ys = points.map { $0.value(of: metric) }
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let spread = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard spread > 0 else { return nil }
        return zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +) / spread
    }
}
