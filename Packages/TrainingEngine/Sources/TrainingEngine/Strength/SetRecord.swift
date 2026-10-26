import Foundation

/// One performed working set. RIR is the athlete's reps-in-reserve estimate when the set ended.
public struct PerformedSet: Codable, Sendable, Hashable {
    public var weightKg: Double
    public var reps: Int
    public var rir: Int

    public init(weightKg: Double, reps: Int, rir: Int) {
        self.weightKg = weightKg
        self.reps = reps
        self.rir = max(0, rir)
    }

    /// Estimated one-rep max using Epley, extended with RIR so a set stopped short
    /// of failure is treated as the longer set it could have been.
    public var estimatedOneRepMax: Double {
        Progression.estimatedOneRepMax(weightKg: weightKg, reps: reps, rir: rir)
    }

    /// Session RPE contribution on the 0 to 10 scale.
    public var rpe: Double { max(0, min(10, 10 - Double(rir))) }
}

/// Everything the generator needs to know about one past exposure to an exercise.
public struct ExerciseHistoryEntry: Codable, Sendable, Hashable {
    public var exerciseID: String
    public var date: Date
    public var targetReps: ClosedRange<Int>
    public var targetRIR: Int
    public var sets: [PerformedSet]

    public init(exerciseID: String, date: Date, targetReps: ClosedRange<Int>, targetRIR: Int, sets: [PerformedSet]) {
        self.exerciseID = exerciseID
        self.date = date
        self.targetReps = targetReps
        self.targetRIR = targetRIR
        self.sets = sets
    }

    public var workingSets: [PerformedSet] { sets.filter { $0.reps > 0 } }

    /// The e1RM this session supports. Uses the median of working sets rather than the
    /// single best so one over-ambitious RIR estimate cannot drive next week's load.
    public var sessionOneRepMax: Double? { sessionOneRepMax(bodyweightKg: 0) }

    /// As above, with bodyweight added to every set's load for bodyweight movements.
    public func sessionOneRepMax(bodyweightKg: Double) -> Double? {
        let values = workingSets.map { Progression.estimatedOneRepMax(weightKg: $0.weightKg + bodyweightKg, reps: $0.reps, rir: $0.rir) }.sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }

    public var meanRIR: Double? {
        let sets = workingSets
        guard !sets.isEmpty else { return nil }
        return Double(sets.map(\.rir).reduce(0, +)) / Double(sets.count)
    }
}
