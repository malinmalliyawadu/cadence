import TrainingEngine

/// How a quality run reads on the run screen and the cards that lead to it.
extension QualityStructure {
    /// The hard part alone: "20 at threshold", "5 × 1 km at interval pace".
    var hardPart: String {
        switch workout {
        case .threshold: "\(Int(workMinutes.rounded())) at threshold"
        case .intervals: "\(repeats) × 1 km at interval pace"
        case .speed: "\(repeats) × 400 m at speed pace"
        }
    }

    /// "15 easy, 5 × 1 km at interval pace with 3 minutes' easy jog between, 15 easy".
    var summary: String {
        let hard = switch workout {
        case .threshold: "\(Int(workMinutes.rounded())) at threshold"
        case .intervals: "\(repeats) × 1 km at interval pace with \(Self.minutes(recoveryMinutes)) minutes' easy jog between"
        case .speed: "\(repeats) × 400 m at speed pace with \(Self.minutes(recoveryMinutes)) minutes' walk or jog between"
        }
        return "\(warmUpMinutes) easy, \(hard), \(coolDownMinutes) easy"
    }

    /// Over the pace band on the run screen: "Interval pace, 5 × 1 km".
    var blockLabel: String {
        switch workout {
        case .threshold: "Threshold pace, \(Int(workMinutes.rounded())) minute block"
        case .intervals: "Interval pace, \(repeats) × 1 km"
        case .speed: "Speed pace, \(repeats) × 400 m"
        }
    }

    /// "3", or "2½" for two and a half.
    private static func minutes(_ value: Double) -> String {
        let whole = Int(value)
        return value - Double(whole) >= 0.5 ? "\(whole)½" : "\(whole)"
    }
}

extension QualityWorkout {
    /// What the workout is for, one sentence.
    var purpose: String {
        switch self {
        case .intervals: "Intervals raise the ceiling: the most oxygen you can use."
        case .threshold: "Threshold lifts the pace you can hold before it starts to bite."
        case .speed: "Speed reps make running fast cheaper. Run them by pace; heart rate lags on reps this short."
        }
    }
}
