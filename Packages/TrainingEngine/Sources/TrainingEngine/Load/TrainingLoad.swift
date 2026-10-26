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

public struct LoadSnapshot: Sendable, Hashable {
    public let asOf: Date
    public let series: [DailyLoad]
    public let weekLoad: Double
    /// Foster monotony: mean daily load over the last 7 days divided by its standard deviation.
    public let monotony: Double?
    /// Foster strain: weekly load multiplied by monotony.
    public let strain: Double?

    public var today: DailyLoad? { series.last }
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
        let weekLoad = lastWeek.reduce(0, +)
        var monotony: Double?
        var strain: Double?
        if lastWeek.count == 7 {
            let mean = weekLoad / 7
            let variance = lastWeek.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 7
            let sd = variance.squareRoot()
            if sd > 0 {
                monotony = mean / sd
                strain = weekLoad * (mean / sd)
            }
        }
        return LoadSnapshot(asOf: asOf, series: series, weekLoad: weekLoad, monotony: monotony, strain: strain)
    }
}

/// Turns a load snapshot into concrete adjustments for the generator and planner.
public struct Readiness: Sendable, Hashable {
    /// Multiplier applied to prescribed strength loads.
    public let loadMultiplier: Double
    /// Sets removed from compound and accessory movements.
    public let setReduction: Int
    /// Multiplier applied to the week's planned training load versus chronic.
    public let weeklyLoadFactor: Double
    public let zone: LoadZone
    public let headline: String

    public static func from(_ snapshot: LoadSnapshot) -> Readiness {
        let zone = snapshot.zone
        switch zone {
        case .building:
            return Readiness(loadMultiplier: 1, setReduction: 0, weeklyLoadFactor: 1.05, zone: zone,
                             headline: "Building your baseline. Train normally and log everything.")
        case .undertrained:
            return Readiness(loadMultiplier: 1, setReduction: 0, weeklyLoadFactor: 1.15, zone: zone,
                             headline: "Load is below your baseline. Room to push this week.")
        case .optimal:
            return Readiness(loadMultiplier: 1, setReduction: 0, weeklyLoadFactor: 1.08, zone: zone,
                             headline: "Load is in the sweet spot. Progress as earned.")
        case .elevated:
            return Readiness(loadMultiplier: 0.95, setReduction: 1, weeklyLoadFactor: 0.95, zone: zone,
                             headline: "Load is climbing fast. Trimming volume a touch this week.")
        case .danger:
            return Readiness(loadMultiplier: 0.9, setReduction: 1, weeklyLoadFactor: 0.85, zone: zone,
                             headline: "Load spiked. This week is a deload: lighter, shorter, more sleep.")
        }
    }
}
