import Foundation

/// A race the athlete might run, for predictions and goals.
public enum RaceDistance: String, Codable, Sendable, CaseIterable, Hashable {
    case fiveK, tenK, half, marathon

    public var kilometres: Double {
        switch self {
        case .fiveK: 5
        case .tenK: 10
        case .half: 21.0975
        case .marathon: 42.195
        }
    }

    public var displayName: String {
        switch self {
        case .fiveK: "5 km"
        case .tenK: "10 km"
        case .half: "Half marathon"
        case .marathon: "Marathon"
        }
    }

    public var shortName: String {
        switch self {
        case .fiveK: "5 km"
        case .tenK: "10 km"
        case .half: "Half"
        case .marathon: "Marathon"
        }
    }

    /// What a goal can be set for. The quality-run rotation (intervals, threshold, speed) is what a
    /// 5 or 10 km is built on; a half or a marathon is built on mileage, which the week does not have.
    public static let goalDistances: [RaceDistance] = [.fiveK, .tenK]
}

/// A time to run a race in: "5 km in 20:00".
public struct RunGoal: Codable, Sendable, Hashable {
    public var distance: RaceDistance
    public var minutes: Double

    public init(distance: RaceDistance, minutes: Double) {
        self.distance = distance
        self.minutes = minutes
    }

    /// The fitness the goal takes, on the same scale as `RunPacing.fitness`.
    public var vdot: Double { RunPacing.rawVDOT(distanceKm: distance.kilometres, minutes: minutes) }
    /// Seconds per kilometre.
    public var pace: Double { minutes * 60 / distance.kilometres }
}

/// Fitness as of one day: the best run of the eight weeks before it.
public struct FitnessPoint: Sendable, Hashable {
    public let date: Date
    public let vdot: Double

    public init(date: Date, vdot: Double) {
        self.date = date
        self.vdot = vdot
    }
}

extension RunPacing {
    /// The VDOT of a run with no checks on whether the run is one to trust.
    static func rawVDOT(distanceKm: Double, minutes: Double) -> Double {
        oxygenCost(metresPerMinute: distanceKm * 1000 / minutes) / sustainableFraction(minutes: minutes)
    }

    /// The time `vdot` runs `distanceKm` in, flat out: Daniels' curves solved for time. VDOT falls as
    /// the time grows, so a bisection between 1:30 and 20:00 a kilometre finds it to well under a second.
    public static func predictedMinutes(distanceKm: Double, vdot: Double) -> Double {
        var fast = distanceKm * 1.5, slow = distanceKm * 20
        for _ in 0..<60 {
            let middle = (fast + slow) / 2
            if rawVDOT(distanceKm: distanceKm, minutes: middle) > vdot { fast = middle } else { slow = middle }
        }
        return (fast + slow) / 2
    }

    /// Fitness once a week for `weeks` weeks up to `now`, oldest first. Weeks with no run worth
    /// reading in the eight before them are left out rather than drawn as zero.
    public static func fitnessHistory(from runs: [RunEffort], through now: Date = .now, weeks: Int = 26) -> [FitnessPoint] {
        (0...max(0, weeks)).reversed().compactMap { back in
            let date = now.addingTimeInterval(-Double(back) * 7 * 86_400)
            return fitness(from: runs, asOf: date).map { FitnessPoint(date: date, vdot: $0) }
        }
    }
}

/// Where the athlete's running stands: predicted race times from current fitness, how fitness has
/// moved, and, with a goal, how far off it is and when the trend reaches it.
public struct RaceOutlook: Sendable, Hashable {
    public let vdot: Double?
    /// Weekly fitness over the last half year, oldest first.
    public let history: [FitnessPoint]
    /// Least-squares slope of fitness over the last twelve weeks, VDOT a week. `nil` without six
    /// weekly readings, so a couple of runs never project anything.
    public let vdotPerWeek: Double?
    public let goal: RunGoal?
    /// Fitness on the day the goal was set, which progress is measured from.
    public let goalStartVDOT: Double?
    /// When the twelve-week trend reaches the goal, if it is rising fast enough to within two years.
    public let projectedDate: Date?

    /// A trend slower than this, VDOT a week, is holding steady, not heading anywhere.
    public static let trendThreshold = 0.05

    public static func evaluate(runs: [RunEffort], goal: RunGoal?, goalStartVDOT: Double? = nil, asOf now: Date = .now) -> RaceOutlook {
        let vdot = RunPacing.fitness(from: runs, asOf: now)
        let history = RunPacing.fitnessHistory(from: runs, through: now)
        let recent = history.filter { $0.date >= now.addingTimeInterval(-12 * 7 * 86_400) }
        let slope = recent.count >= 6 ? slopePerWeek(recent) : nil

        var projected: Date?
        if let goal, let vdot, let slope, slope >= trendThreshold, goal.vdot > vdot {
            let weeks = (goal.vdot - vdot) / slope
            if weeks <= 104 { projected = now.addingTimeInterval(weeks * 7 * 86_400) }
        }
        return RaceOutlook(vdot: vdot, history: history, vdotPerWeek: slope, goal: goal, goalStartVDOT: goalStartVDOT, projectedDate: projected)
    }

    /// Flat-out time for `distance` today, minutes.
    public func predictedMinutes(for distance: RaceDistance) -> Double? {
        vdot.map { RunPacing.predictedMinutes(distanceKm: distance.kilometres, vdot: $0) }
    }

    /// Predicted time for the goal distance minus the goal, minutes. Zero or less means the goal is met.
    public var goalGap: Double? {
        guard let goal, let predicted = predictedMinutes(for: goal.distance) else { return nil }
        return predicted - goal.minutes
    }

    public var goalIsMet: Bool { (goalGap ?? 1) <= 0 }

    /// How much of the way from fitness on the day the goal was set to the goal's fitness has been
    /// covered, 0 to 1. `nil` without a starting point to measure from.
    public var goalProgress: Double? {
        guard let goal, let vdot, let start = goalStartVDOT else { return nil }
        guard goal.vdot > start else { return 1 }
        return min(1, max(0, (vdot - start) / (goal.vdot - start)))
    }

    private static func slopePerWeek(_ points: [FitnessPoint]) -> Double? {
        guard let origin = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(origin) / (7 * 86_400) }
        let ys = points.map(\.vdot)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let spread = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard spread > 0 else { return nil }
        return zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +) / spread
    }
}

/// What a quality run is. Without a goal it is always a threshold run. Training for a race it turns
/// over week by week: intervals at VO2max pace, threshold, then short speed reps, which between them
/// raise the ceiling, the pace that can be held, and the economy of running fast.
public enum QualityWorkout: String, Codable, Sendable, CaseIterable, Hashable {
    case intervals, threshold, speed

    public var displayName: String {
        switch self {
        case .intervals: "Intervals"
        case .threshold: "Threshold run"
        case .speed: "Speed reps"
        }
    }

    /// The heart-rate zone of the hard part. Speed reps are too short for heart rate to catch up,
    /// so they are run by pace.
    public var zone: Int {
        switch self {
        case .intervals, .speed: 5
        case .threshold: 4
        }
    }

    /// The week's workout when training for a goal. Counted in weeks from a fixed Monday, so it never
    /// depends on when the week was planned, and every week of three gets one of each.
    public static func rotation(weekStart: Date, calendar: Calendar) -> QualityWorkout {
        let epoch = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? .distantPast
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: epoch), to: calendar.startOfDay(for: weekStart)).day ?? 0
        let week = Int((Double(days) / 7).rounded(.down))
        return allCases[((week % 3) + 3) % 3]
    }
}

/// The shape of a quality run sized to its planned minutes: an easy warm-up, the hard part, an
/// easy cool-down. The hard part takes what the warm-up and cool-down (ten minutes each at least)
/// leave, within the bounds that keep it the workout it is.
public struct QualityStructure: Sendable, Hashable {
    public let workout: QualityWorkout
    public let warmUpMinutes: Int
    /// How many repeats; 1 for a threshold run.
    public let repeats: Int
    /// Each repeat's distance, for intervals and speed reps.
    public let repeatKm: Double?
    /// The threshold block, or one repeat's time at its pace.
    public let workMinutes: Double
    /// Easy jogging between repeats.
    public let recoveryMinutes: Double
    public let coolDownMinutes: Int

    public static func fitting(_ workout: QualityWorkout, plannedMinutes: Double, pace: PaceRange?) -> QualityStructure {
        let available = max(0, plannedMinutes - 20)
        let repeatPace = pace.map { ($0.fastest + $0.slowest) / 2 }
        let repeats: Int, repeatKm: Double?, work: Double, recovery: Double
        switch workout {
        case .threshold:
            repeats = 1; repeatKm = nil; recovery = 0
            work = min(30, max(15, (available / 5).rounded(.down) * 5))
        case .intervals:
            repeatKm = 1; recovery = 3
            work = (repeatPace ?? 300) / 60
            repeats = min(6, max(3, Int(((available + recovery) / (work + recovery)).rounded(.down))))
        case .speed:
            repeatKm = 0.4; recovery = 2.5
            work = (repeatPace ?? 120 / 0.4) * 0.4 / 60
            repeats = min(8, max(4, Int(((available + recovery) / (work + recovery)).rounded(.down))))
        }
        let core = Double(repeats) * work + Double(repeats - 1) * recovery
        let spare = Int((plannedMinutes - core).rounded())
        let warmUp = max(10, Int((Double(spare) / 2).rounded(.up)))
        let coolDown = max(10, spare - warmUp)
        return QualityStructure(workout: workout, warmUpMinutes: warmUp, repeats: repeats, repeatKm: repeatKm,
                                workMinutes: work, recoveryMinutes: recovery, coolDownMinutes: coolDown)
    }

    public var totalMinutes: Double {
        Double(warmUpMinutes + coolDownMinutes) + Double(repeats) * workMinutes + Double(repeats - 1) * recoveryMinutes
    }
}
