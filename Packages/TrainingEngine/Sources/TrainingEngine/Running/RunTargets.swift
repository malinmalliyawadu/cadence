import Foundation

/// One finished run, as much as pacing needs.
public struct RunEffort: Sendable, Hashable {
    public var date: Date
    public var distanceKm: Double
    public var minutes: Double

    public init(date: Date, distanceKm: Double, minutes: Double) {
        self.date = date
        self.distanceKm = distanceKm
        self.minutes = minutes
    }

    /// Seconds per kilometre.
    public var pace: Double { minutes * 60 / distanceKm }
}

/// A pace band in seconds per kilometre. `fastest` is the smaller number.
public struct PaceRange: Sendable, Hashable {
    public var fastest: Double
    public var slowest: Double

    public init(fastest: Double, slowest: Double) {
        self.fastest = min(fastest, slowest)
        self.slowest = max(fastest, slowest)
    }

    /// Rounded to five seconds either way, so the band reads like something a watch can hold.
    public var rounded: PaceRange {
        PaceRange(fastest: (fastest / 5).rounded() * 5, slowest: (slowest / 5).rounded() * 5)
    }
}

/// Heart-rate zones from a maximum and, when known, a resting rate. With a resting rate the
/// zones are fractions of heart-rate reserve (Karvonen), which fits trained runners far better
/// than plain percentages of max.
public struct HeartRateZones: Sendable, Hashable {
    public var maximum: Int
    public var resting: Int?

    public init(maximum: Int, resting: Int? = nil) {
        self.maximum = maximum
        self.resting = resting
    }

    /// Lower and upper fraction for zones 1 to 5.
    static let bounds: [ClosedRange<Double>] = [0.50...0.60, 0.60...0.70, 0.70...0.80, 0.80...0.90, 0.90...1.0]

    public func range(zone: Int) -> ClosedRange<Int> {
        let fractions = Self.bounds[max(1, min(5, zone)) - 1]
        let floor = Double(resting ?? 0)
        let reserve = Double(maximum) - floor
        let low = Int((floor + reserve * fractions.lowerBound).rounded())
        let high = Int((floor + reserve * fractions.upperBound).rounded())
        return low...high
    }

    /// The maximum to plan from: the higher of what the athlete has actually reached and the
    /// age prediction (Tanaka, 208 minus 0.7 times age). Easy runners rarely touch their true max,
    /// so an observed figure only wins when it is higher. The third-highest daily peak is used
    /// rather than the highest, so a single optical-sensor spike cannot set the zones.
    public static func estimatedMaximum(dailyPeaks: [Double], age: Int?) -> Int? {
        let peaks = dailyPeaks.filter { $0 >= 100 && $0 <= 230 }.sorted(by: >)
        let observed = peaks.count >= 5 ? peaks[2] : peaks.first
        let predicted = age.map { 208 - 0.7 * Double($0) }
        guard let best = [observed, predicted].compactMap({ $0 }).max() else { return nil }
        return Int(best.rounded())
    }
}

/// What a run should be run at: a pace band and a heart-rate zone. Pace is the primary target;
/// the zone is the check that the pace is right on the day (heat, hills, fatigue).
public struct RunTarget: Sendable, Hashable {
    public let kind: RunKind
    /// The pace for the run, or for a quality run its main block. `nil` with no recent runs.
    public let pace: PaceRange?
    /// Warm-up and cool-down pace for a quality run.
    public let easyPace: PaceRange?
    public let zone: Int
    public let heartRate: ClosedRange<Int>?
    /// For a quality run: which workout, and its shape sized to the planned minutes.
    public let workout: QualityWorkout?
    public let structure: QualityStructure?

    init(kind: RunKind, pace: PaceRange?, easyPace: PaceRange? = nil, zone: Int, heartRate: ClosedRange<Int>?, workout: QualityWorkout? = nil, structure: QualityStructure? = nil) {
        self.kind = kind
        self.pace = pace
        self.easyPace = easyPace
        self.zone = zone
        self.heartRate = heartRate
        self.workout = workout
        self.structure = structure
    }
}

/// Training paces from recent runs, using Daniels' oxygen-cost and time-to-exhaustion curves.
/// Every run gives a VDOT; the best of the last eight weeks is the athlete's current fitness,
/// since easy and long runs are deliberately below it and only underestimate.
public enum RunPacing {
    /// Oxygen cost of running at `metresPerMinute`, ml/kg/min.
    static func oxygenCost(metresPerMinute v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Fraction of VO2max sustainable for `minutes`.
    static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// The VDOT a run implies, or `nil` for runs too short or too odd to trust (GPS glitches, walks).
    public static func vdot(distanceKm: Double, minutes: Double) -> Double? {
        guard distanceKm >= 3, minutes >= 12 else { return nil }
        let pace = minutes * 60 / distanceKm
        guard pace >= 170, pace <= 720 else { return nil } // 2:50 to 12:00 per km
        return oxygenCost(metresPerMinute: distanceKm * 1000 / minutes) / sustainableFraction(minutes: minutes)
    }

    /// Current fitness from runs in the last `windowDays`.
    public static func fitness(from runs: [RunEffort], asOf now: Date = .now, windowDays: Int = 56) -> Double? {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        return runs.filter { $0.date >= start && $0.date <= now }.compactMap { vdot(distanceKm: $0.distanceKm, minutes: $0.minutes) }.max()
    }

    /// Seconds per kilometre at which running costs `fraction` of `vdot`.
    public static func pace(fraction: Double, of vdot: Double) -> Double {
        let target = fraction * vdot
        // Solve 0.000104 v^2 + 0.182258 v - (4.60 + target) = 0 for v in metres per minute.
        let a = 0.000104, b = 0.182258, c = -(4.60 + target)
        let v = (-b + sqrt(b * b - 4 * a * c)) / (2 * a)
        return 60_000 / v
    }

    static func band(_ fractions: ClosedRange<Double>, of vdot: Double) -> PaceRange {
        PaceRange(fastest: pace(fraction: fractions.upperBound, of: vdot), slowest: pace(fraction: fractions.lowerBound, of: vdot)).rounded
    }

    /// Easy runs sit at 65 to 74% of VDOT, long runs a touch gentler. A quality run's hard part is
    /// threshold at 86 to 88%, intervals at 97 to 100% (VO2max pace, Daniels' I), or speed reps at
    /// the pace of a flat-out mile (Daniels' R). `plannedMinutes` sizes a quality run's structure.
    public static func target(for kind: RunKind, vdot: Double?, zones: HeartRateZones?, workout: QualityWorkout = .threshold, plannedMinutes: Double? = nil) -> RunTarget {
        let easy = vdot.map { band(0.65...0.74, of: $0) }
        switch kind {
        case .easy:
            return RunTarget(kind: kind, pace: easy, zone: 2, heartRate: zones?.range(zone: 2))
        case .long:
            return RunTarget(kind: kind, pace: vdot.map { band(0.62...0.72, of: $0) }, zone: 2, heartRate: zones?.range(zone: 2))
        case .quality:
            let pace = vdot.map { workPace(workout, vdot: $0) }
            let structure = plannedMinutes.map { QualityStructure.fitting(workout, plannedMinutes: $0, pace: pace) }
            return RunTarget(kind: kind, pace: pace, easyPace: easy, zone: workout.zone, heartRate: zones?.range(zone: workout.zone),
                             workout: workout, structure: structure)
        }
    }

    static func workPace(_ workout: QualityWorkout, vdot: Double) -> PaceRange {
        switch workout {
        case .threshold: return band(0.86...0.88, of: vdot)
        case .intervals: return band(0.97...1.0, of: vdot)
        case .speed:
            let mile = 1.609344
            let pace = predictedMinutes(distanceKm: mile, vdot: vdot) * 60 / mile
            let rounded = PaceRange(fastest: pace - 3, slowest: pace + 3).rounded
            return rounded.fastest == rounded.slowest ? PaceRange(fastest: rounded.fastest, slowest: rounded.slowest + 5) : rounded
        }
    }
}
