import Foundation

/// The three things Cadence plans. Everything in the engine is keyed off this.
public enum Modality: String, Codable, Sendable, CaseIterable, Hashable {
    case strength
    case running
    case yoga

    public var displayName: String {
        switch self {
        case .strength: "Strength"
        case .running: "Run"
        case .yoga: "Hot yoga"
        }
    }
}

/// The half of the body a strength session trains. Cadence runs an upper/lower split.
public enum BodyHalf: String, Codable, Sendable, CaseIterable, Hashable {
    case upper
    case lower

    public var displayName: String {
        switch self {
        case .upper: "Upper"
        case .lower: "Lower"
        }
    }
}

/// How a run should feel. Drives the planner's load allocation and the day-spacing rules.
public enum RunKind: String, Codable, Sendable, CaseIterable, Hashable {
    case easy
    case long
    case quality   // tempo / intervals

    public var displayName: String {
        switch self {
        case .easy: "Easy run"
        case .long: "Long run"
        case .quality: "Quality run"
        }
    }

    /// Typical session RPE used when the athlete has not rated the run yet.
    public var defaultRPE: Double {
        switch self {
        case .easy: 4
        case .long: 6
        case .quality: 8
        }
    }

    /// Whether the run counts as "hard" for spacing against lower-body strength days.
    public var isHard: Bool { self != .easy }

    /// Duration used when there is no load budget to size the run from.
    public var defaultMinutes: Double {
        switch self {
        case .easy: 40
        case .long: 75
        case .quality: 40
        }
    }
}

/// Rounds a weight down to the nearest loadable increment.
public func roundToIncrement(_ weight: Double, increment: Double) -> Double {
    guard increment > 0 else { return weight }
    return (weight / increment).rounded(.down) * increment
}
