import Foundation

/// One lighter set before a movement's working sets. Warm-ups are suggestions to tick off, not
/// logged sets: they never reach progression, load or Apple Health.
public struct WarmUpSet: Codable, Sendable, Hashable {
    public let weightKg: Double
    public let reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// The ramp to a movement's working weight, modelled on how the athlete warms up in their own
/// log: one set of 8 at about 60% before every machine, cable, Smith and barbell movement, and a
/// second set of 3 at about 85% once the working load reaches 100 kg (leg press: 120 x 8 and
/// 160 x 3 before 180). Light work where a warm-up costs more than it gives goes straight in:
/// raises, calves, forearms, core, hip abduction and kickbacks, dumbbell isolation, bodyweight.
public enum WarmUp {
    /// Working load from which a second, heavier ramp set is worth it.
    public static let heavyLoadKg: Double = 100

    public static func needsWarmUp(_ exercise: Exercise) -> Bool {
        switch exercise.pattern {
        case .lateralRaise, .wristFlexion, .calfRaise, .coreBrace: return false
        default: break
        }
        switch exercise.equipment {
        case .bodyweight: return false
        // Changing dumbbells for a set is a chore; only the heavy presses earn it.
        case .dumbbell, .kettlebell: return exercise.role == .compound
        case .barbell, .cable, .machine, .smith: break
        }
        if exercise.role == .isolation, [.forearms, .glutes].contains(exercise.primary) { return false }
        return true
    }

    /// The warm-up sets before working at `workingWeightKg`, lightest first. Empty when the
    /// movement needs none or there is no working weight yet to ramp to.
    public static func sets(for exercise: Exercise, workingWeightKg: Double?) -> [WarmUpSet] {
        guard needsWarmUp(exercise), let working = workingWeightKg, working > 0 else { return [] }
        let increment = exercise.equipment.incrementKg
        var steps: [(fraction: Double, reps: Int)] = [(0.6, 8)]
        if working >= heavyLoadKg { steps.append((0.85, 3)) }

        var ramp: [WarmUpSet] = []
        for step in steps {
            let weight = roundToIncrement(working * step.fraction, increment: increment)
            // A step that rounds to nothing, to the working weight, or onto the step before adds nothing.
            let floor = ramp.last?.weightKg ?? 0
            guard weight > floor, working > weight else { continue }
            ramp.append(WarmUpSet(weightKg: weight, reps: step.reps))
        }
        return ramp
    }
}
