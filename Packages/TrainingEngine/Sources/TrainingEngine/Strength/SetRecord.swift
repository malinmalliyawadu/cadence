import Foundation

/// One performed working set. RIR is the athlete's reps-in-reserve estimate when the set
/// ended, and is only asked for on an exercise's final set: that set is the closest to
/// failure, so it is the most honest estimate, and it is the one the target RIR refers to.
public struct PerformedSet: Codable, Sendable, Hashable {
    public var weightKg: Double
    public var reps: Int
    public var rir: Int?

    public init(weightKg: Double, reps: Int, rir: Int? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir.map { max(0, $0) }
    }

    /// Estimated one-rep max using Epley, extended with RIR so a set stopped short
    /// of failure is treated as the longer set it could have been. `nil` for an unrated set.
    public var estimatedOneRepMax: Double? {
        rir.map { Progression.estimatedOneRepMax(weightKg: weightKg, reps: reps, rir: $0) }
    }
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

    /// The sets that carry an RIR. When none do (the athlete stopped before the final set,
    /// or the history was imported), the last working set is taken to have landed on the
    /// target, so progression still has an estimate to work from.
    public var ratedSets: [PerformedSet] {
        let working = workingSets
        let rated = working.filter { $0.rir != nil }
        if !rated.isEmpty { return rated }
        guard var last = working.last else { return [] }
        last.rir = targetRIR
        return [last]
    }

    /// The e1RM this session supports, from the rated sets. With one rated set per exercise
    /// that is the final set; where several are rated (older logs rated every set) the median
    /// is used, so one over-ambitious estimate cannot drive next week's load.
    public var sessionOneRepMax: Double? { sessionOneRepMax(bodyweightKg: 0) }

    /// As above, with bodyweight added to every set's load for bodyweight movements.
    public func sessionOneRepMax(bodyweightKg: Double) -> Double? {
        let values = ratedSets.compactMap { set in set.rir.map { Progression.estimatedOneRepMax(weightKg: set.weightKg + bodyweightKg, reps: set.reps, rir: $0) } }.sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }

    public var meanRIR: Double? {
        let rirs = ratedSets.compactMap(\.rir)
        guard !rirs.isEmpty else { return nil }
        return Double(rirs.reduce(0, +)) / Double(rirs.count)
    }
}
