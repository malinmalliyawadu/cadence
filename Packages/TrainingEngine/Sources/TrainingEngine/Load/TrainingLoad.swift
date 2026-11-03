import Foundation

/// One session's contribution to training load, in session-RPE arbitrary units (RPE x minutes).
/// Using one scale for lifting, running and yoga is the whole point: it lets the planner
/// trade a long run against a lower day instead of treating them as unrelated.
public struct LoadEntry: Codable, Sendable, Hashable {
    public var date: Date
    public var modality: Modality
    public var load: Double

    public init(date: Date, modality: Modality, load: Double) {
        self.date = date
        self.modality = modality
        self.load = load
    }
}

public enum TrainingLoad {
    /// Session RPE for a lifting session from its mean RIR. Rest between sets means a
    /// 2 RIR session does not feel like an RPE 8 run, hence the offset.
    public static func strengthSessionRPE(meanRIR: Double) -> Double {
        min(9, max(3, 8.5 - meanRIR))
    }

    public static func sessionLoad(rpe: Double, minutes: Double) -> Double {
        max(0, rpe) * max(0, minutes)
    }
}

/// A day's load picture, produced by `LoadAnalysis`.
public struct DailyLoad: Sendable, Hashable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let load: Double
    /// Exponentially weighted 7-day acute load.
    public let acute: Double
    /// Exponentially weighted 28-day chronic load.
    public let chronic: Double

    /// Acute:chronic workload ratio. `nil` until there is enough history for a chronic baseline.
    public var acwr: Double? {
        chronic > 20 ? acute / chronic : nil
    }
}

public enum LoadZone: String, Sendable, Hashable {
    case building      // no baseline yet
    case undertrained  // acwr < 0.8
    case optimal       // 0.8 ... 1.3
    case elevated      // 1.3 ... 1.5
    case danger        // > 1.5

    public static func zone(for acwr: Double?) -> LoadZone {
        guard let acwr else { return .building }
        switch acwr {
        case ..<0.8: return .undertrained
        case ..<1.3: return .optimal
        case ..<1.5: return .elevated
        default: return .danger
        }
    }

    public var displayName: String {
        switch self {
        case .building: "Building baseline"
        case .undertrained: "Under-reaching"
        case .optimal: "Sweet spot"
        case .elevated: "Elevated"
        case .danger: "Spike"
        }
    }
}

/// Foster's picture of the seven days ending on `date`: their total, and how evenly it was spread.
public struct WeeklyLoad: Sendable, Hashable, Identifiable {
    public var id: Date { date }
    /// The last of the seven days.
    public let date: Date
    /// The seven days' load, summed.
    public let load: Double
    /// Mean daily load.
    public let mean: Double
    /// Standard deviation of daily load: how much the days differ.
    public let spread: Double

    /// Mean over spread. High when every day is much the same, low when hard days are followed
    /// by easy ones. Nil when every day was the same, rest included.
    public var monotony: Double? { spread > 0 ? mean / spread : nil }
    /// Weekly load times monotony: a big week counts for more when it was also a flat one.
    public var strain: Double? { monotony.map { load * $0 } }

    public init(date: Date, days: [Double]) {
        let total = days.reduce(0, +)
        let mean = days.isEmpty ? 0 : total / Double(days.count)
        let variance = days.isEmpty ? 0 : days.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(days.count)
        self.date = date
        load = total
        self.mean = mean
        spread = variance.squareRoot()
    }
}

public struct LoadSnapshot: Sendable, Hashable {
    public let asOf: Date
    public let series: [DailyLoad]
    public let weekLoad: Double
    /// Foster monotony: mean daily load over the last 7 days divided by its standard deviation.
    public let monotony: Double?
    /// Foster strain: weekly load multiplied by monotony.
    public let strain: Double?

    public var today: DailyLoad? { series.last }
    /// The seven days ending on each day of the series, from its seventh day on.
    public var weekly: [WeeklyLoad] {
        guard series.count >= 7 else { return [] }
        return (6..<series.count).map { end in
            WeeklyLoad(date: series[end].date, days: series[(end - 6)...end].map(\.load))
        }
    }
    public var acwr: Double? { today?.acwr }
    public var zone: LoadZone { LoadZone.zone(for: acwr) }
}

/// Exponentially weighted ACWR (Williams et al. 2017) plus Foster monotony and strain.
/// EWMA is used instead of rolling averages because it weights yesterday more than
/// 27 days ago, which is how fatigue actually behaves, and because it has no cliff
/// when a big session falls out of the window.
public enum LoadAnalysis {
    public static let acuteDays = 7.0
    public static let chronicDays = 28.0
    /// Foster's line: above this, the week was too flat for the hard days to be absorbed.
    public static let monotonyLimit = 2.0

    /// Snapshot for planning a week that starts on `planningDate`. Uses the last completed
    /// day as the reference point: including a still-empty "today" would dilute the acute
    /// load with a zero and make every Monday morning look like a taper.
    public static func snapshot(entries: [LoadEntry], planningOn planningDate: Date, calendar: Calendar = .current) -> LoadSnapshot {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: planningDate) ?? planningDate
        return snapshot(entries: entries, asOf: yesterday, calendar: calendar)
    }

    /// Snapshot including every entry up to and including `asOf`'s day.
    public static func snapshot(entries: [LoadEntry], asOf: Date, calendar: Calendar = .current, lookbackDays: Int = 90) -> LoadSnapshot {
        let end = calendar.startOfDay(for: asOf)
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: end) else {
            return LoadSnapshot(asOf: asOf, series: [], weekLoad: 0, monotony: nil, strain: nil)
        }

        var byDay: [Date: Double] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= start, day <= end else { continue }
            byDay[day, default: 0] += entry.load
        }

        let lambdaA = 2 / (acuteDays + 1)
        let lambdaC = 2 / (chronicDays + 1)
        var acute = 0.0
        var chronic = 0.0
        var series: [DailyLoad] = []
        var day = start
        while day <= end {
            let load = byDay[day] ?? 0
            acute = load * lambdaA + (1 - lambdaA) * acute
            chronic = load * lambdaC + (1 - lambdaC) * chronic
            series.append(DailyLoad(date: day, load: load, acute: acute, chronic: chronic))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let lastWeek = series.suffix(7).map(\.load)
        let week = lastWeek.count == 7 ? WeeklyLoad(date: end, days: lastWeek) : nil
        return LoadSnapshot(asOf: asOf, series: series, weekLoad: lastWeek.reduce(0, +), monotony: week?.monotony, strain: week?.strain)
    }
}

/// Turns a load snapshot, and today's recovery when there is one, into concrete adjustments
/// for the generator and planner.
public struct Readiness: Sendable, Hashable {
    /// Multiplier applied to prescribed strength loads: the lower of what load and recovery call for.
    public let loadMultiplier: Double
    /// Sets removed from compound and accessory movements.
    public let setReduction: Int
    /// Multiplier applied to the week's planned training load versus chronic. Load only: one
    /// morning's recovery says nothing about Saturday.
    public let weeklyLoadFactor: Double
    public let zone: LoadZone
    public let headline: String
    public let recovery: RecoveryStatus?

    /// Why loads are trimmed, as a clause for the movement's rationale, when recovery rather than
    /// load sets the multiplier. Nil when load does, or nothing is trimmed.
    public var cutReason: String? {
        guard let recovery, recovery.loadMultiplier < 1, recovery.loadMultiplier < loadOnlyMultiplier else { return nil }
        return recovery.reason
    }

    private let loadOnlyMultiplier: Double

    private init(loadMultiplier: Double, setReduction: Int, weeklyLoadFactor: Double, zone: LoadZone, headline: String, recovery: RecoveryStatus?) {
        self.loadOnlyMultiplier = loadMultiplier
        self.loadMultiplier = min(loadMultiplier, recovery?.loadMultiplier ?? 1)
        self.setReduction = setReduction
        self.weeklyLoadFactor = weeklyLoadFactor
        self.zone = zone
        self.headline = headline
        self.recovery = recovery
    }

    /// - Parameter recovery: today's recovery. Pass it only for a session on the day it was measured.
    public static func from(_ snapshot: LoadSnapshot, recovery: RecoveryStatus? = nil) -> Readiness {
        from(zone: snapshot.zone, recovery: recovery)
    }

    /// What a load zone does to the week, before recovery is taken into account.
    public static func from(zone: LoadZone, recovery: RecoveryStatus? = nil) -> Readiness {
        switch zone {
        case .building:
            return Readiness(loadMultiplier: 1, setReduction: 0, weeklyLoadFactor: 1.05, zone: zone,
                             headline: "Building your baseline. Train normally and log everything.", recovery: recovery)
        case .undertrained:
            return Readiness(loadMultiplier: 1, setReduction: 0, weeklyLoadFactor: 1.15, zone: zone,
                             headline: "Load is below your baseline. Room to push this week.", recovery: recovery)
        case .optimal:
            return Readiness(loadMultiplier: 1, setReduction: 0, weeklyLoadFactor: 1.08, zone: zone,
                             headline: "Load is in the sweet spot. Progress as earned.", recovery: recovery)
        case .elevated:
            return Readiness(loadMultiplier: 0.95, setReduction: 1, weeklyLoadFactor: 0.95, zone: zone,
                             headline: "Load is climbing fast. Trimming volume a touch this week.", recovery: recovery)
        case .danger:
            return Readiness(loadMultiplier: 0.9, setReduction: 1, weeklyLoadFactor: 0.85, zone: zone,
                             headline: "Load spiked. This week is a deload: lighter, shorter, more sleep.", recovery: recovery)
        }
    }
}
