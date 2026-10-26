import Foundation

/// A single exercise prescription inside a generated session.
public struct ExercisePrescription: Codable, Sendable, Hashable, Identifiable {
    public var id: String { exercise.id }
    public let exercise: Exercise
    public let sets: Int
    public let repRange: ClosedRange<Int>
    public let targetRIR: Int
    /// Suggested working weight in kilograms. `nil` means "find your weight today":
    /// there is no history and the exercise is one where a guess would be unhelpful.
    public let weightKg: Double?
    public let isFocus: Bool
    public let rationale: String

    public init(exercise: Exercise, sets: Int, repRange: ClosedRange<Int>, targetRIR: Int, weightKg: Double?, isFocus: Bool, rationale: String) {
        self.exercise = exercise
        self.sets = sets
        self.repRange = repRange
        self.targetRIR = targetRIR
        self.weightKg = weightKg
        self.isFocus = isFocus
        self.rationale = rationale
    }

    /// Estimated minutes including rest, used by the planner's load model.
    public var estimatedMinutes: Double {
        let restSeconds: Double = switch exercise.role {
        case .compound: 150
        case .accessory: 105
        case .isolation: 75
        }
        let perSet = Double(repRange.upperBound) * exercise.secondsPerRep + restSeconds
        return perSet * Double(sets) / 60
    }
}

/// What happened last time, distilled into a decision for next time.
public enum ProgressionDecision: String, Codable, Sendable, Hashable {
    case start        // no history
    case increase     // RIR was above target: add load
    case hold         // RIR on target: repeat and chase reps
    case reduce       // RIR was below target or reps missed: back off
    case deload       // stalled across several sessions
    case readinessCut // load management from the planner trimmed the session
}

public struct ProgressionResult: Sendable, Hashable {
    public let weightKg: Double?
    public let decision: ProgressionDecision
    public let rationale: String
}

/// RIR-driven autoregulated progression. The core idea: the final working set gives us
/// an estimated one-rep max (weight at reps + RIR), and the next prescription is
/// whatever load would put the target rep range at the target RIR on that final set. That makes
/// progression continuous rather than "add 2.5 kg if you hit 3x8": a great day
/// earns more, a bad day earns a smaller step back, and the athlete never has to
/// decide what to load.
public enum Progression {
    /// Epley with RIR folded in as unperformed reps.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int, rir: Int) -> Double {
        let repsToFailure = Double(reps + max(0, rir))
        guard repsToFailure > 1 else { return weightKg }
        return weightKg * (1 + repsToFailure / 30)
    }

    /// Inverse of `estimatedOneRepMax`: the load that makes `reps` at `rir` land on `oneRepMax`.
    public static func load(forOneRepMax oneRepMax: Double, reps: Int, rir: Int) -> Double {
        let repsToFailure = Double(reps + max(0, rir))
        return oneRepMax / (1 + repsToFailure / 30)
    }

    /// Decides the next working weight for an exercise.
    /// - Parameters:
    ///   - history: past exposures, any order. Only the three most recent matter.
    ///   - repRange: the rep range the next session will prescribe.
    ///   - targetRIR: the RIR the next session will prescribe.
    ///   - readiness: multiplier from load management, 1.0 when fresh. Values below 1 cut load.
    ///   - bodyweightKg: the athlete's bodyweight. For bodyweight movements (dips, pull-ups) the
    ///     logged weight is the *added* load, so the e1RM is computed on bodyweight plus added load
    ///     and the prescription is converted back to added load. Ignored for everything else.
    public static func nextLoad(
        for exercise: Exercise,
        history: [ExerciseHistoryEntry],
        repRange: ClosedRange<Int>,
        targetRIR: Int,
        readiness: Double = 1.0,
        bodyweightKg: Double = 0
    ) -> ProgressionResult {
        let increment = exercise.equipment.incrementKg
        let base = exercise.equipment == .bodyweight ? max(0, bodyweightKg) : 0
        let recent = history
            .filter { $0.exerciseID == exercise.id && !$0.workingSets.isEmpty }
            .sorted { $0.date > $1.date }
            .prefix(3)

        guard let last = recent.first, let lastE1RM = last.sessionOneRepMax(bodyweightKg: base) else {
            let start = exercise.startingWeightKg > 0 ? roundToIncrement(exercise.startingWeightKg * readiness, increment: increment) : nil
            return ProgressionResult(weightKg: start, decision: .start, rationale: start == nil
                ? "First time on this movement. Work up to a weight where \(repRange.lowerBound) reps leaves \(targetRIR) in reserve."
                : "First time on this movement. Starting conservatively; log honest RIR and the load will self-correct next week.")
        }

        // Stall detection: three sessions with no e1RM growth means fatigue is masking fitness.
        if recent.count == 3 {
            let e1rms = recent.compactMap { $0.sessionOneRepMax(bodyweightKg: base) }
            if e1rms.count == 3, e1rms[0] <= e1rms[1] * 1.005, e1rms[1] <= e1rms[2] * 1.005 {
                let deload = roundToIncrement(lastE1RM * 0.9 / (1 + Double(repRange.lowerBound + targetRIR) / 30) - base, increment: increment)
                return ProgressionResult(weightKg: max(0, deload), decision: .deload, rationale: "No progress across three sessions. Dropping 10% for a week so you come back stronger.")
            }
        }

        // The load that puts the bottom of the rep range at the target RIR. Using the
        // bottom of the range means the athlete can grow into the top before the weight moves.
        // For bodyweight movements this is the added load, which can legitimately be zero.
        let ideal = load(forOneRepMax: lastE1RM, reps: repRange.lowerBound, rir: targetRIR) * readiness - base
        let lastWeight = last.workingSets.map(\.weightKg).max() ?? ideal
        let lastMeanRIR = last.meanRIR ?? Double(targetRIR)
        let hitTopOfRange = last.workingSets.allSatisfy { $0.reps >= last.targetReps.upperBound }

        // Never jump more than two increments in one go: the e1RM estimate gets noisy
        // when RIR is high and we would rather be right over four weeks than bold once.
        let maxUp = lastWeight + increment * 2
        let maxDown = lastWeight - increment * 2
        var next = roundToIncrement(min(max(ideal, max(maxDown, 0)), maxUp), increment: increment)

        let decision: ProgressionDecision
        let rationale: String
        if readiness < 0.97 {
            decision = .readinessCut
            rationale = "Training load is running high this week, so this is \(Int((1 - readiness) * 100))% lighter than you have earned. Keep the RIR honest."
        } else if lastMeanRIR >= Double(last.targetRIR) + 1 {
            next = max(next, roundToIncrement(lastWeight + increment, increment: increment))
            decision = .increase
            rationale = "Last time finished \(formatRIR(lastMeanRIR)) in reserve against a target of \(last.targetRIR). Adding load."
        } else if hitTopOfRange && lastMeanRIR >= Double(last.targetRIR) {
            next = max(next, roundToIncrement(lastWeight + increment, increment: increment))
            decision = .increase
            rationale = "Every set reached \(last.targetReps.upperBound) reps with \(formatRIR(lastMeanRIR)) in reserve. Adding load."
        } else if lastMeanRIR <= Double(last.targetRIR) - 1 {
            next = min(next, lastWeight)
            decision = .reduce
            rationale = "Last time finished \(formatRIR(lastMeanRIR)) in reserve, below the \(last.targetRIR) target. Easing back so every set stays clean."
        } else {
            next = roundToIncrement(lastWeight, increment: increment)
            decision = .hold
            rationale = "Right on target last time. Same weight; aim for one more rep per set."
        }

        return ProgressionResult(weightKg: max(next, 0), decision: decision, rationale: rationale)
    }

    private static func formatRIR(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
