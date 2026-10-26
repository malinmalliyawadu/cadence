import Foundation

/// A set and rep scheme the athlete can switch a movement to for one session, to keep training
/// fresh. Progression reads the final set's actual weight, reps and RIR, so next week's
/// prescription is sound whatever scheme was used this week.
public struct SchemePreset: Sendable, Hashable, Identifiable {
    public let name: String
    public let sets: Int
    public let reps: ClosedRange<Int>
    /// Roles the scheme makes sense for: five heavy sets of lateral raises does not.
    public let roles: Set<ExerciseRole>

    public var id: String { name }

    public static let all: [SchemePreset] = [
        SchemePreset(name: "Heavy", sets: 5, reps: 4...6, roles: [.compound, .accessory]),
        SchemePreset(name: "Strength", sets: 4, reps: 6...8, roles: [.compound, .accessory]),
        SchemePreset(name: "Hypertrophy", sets: 3, reps: 8...12, roles: [.compound, .accessory, .isolation]),
        SchemePreset(name: "Volume", sets: 4, reps: 12...15, roles: [.accessory, .isolation]),
        SchemePreset(name: "Pump", sets: 2, reps: 15...20, roles: [.isolation]),
    ]

    public static func presets(for role: ExerciseRole) -> [SchemePreset] {
        all.filter { $0.roles.contains(role) }
    }
}

extension Progression {
    /// The working weight for a scheme the athlete picked this session, straight from the most
    /// recent estimated one-rep max. Unlike `nextLoad` there is no step cap: moving from eights
    /// to fives is a deliberate change of rep range, not a jump in fitness. `nil` without history.
    public static func load(
        for exercise: Exercise,
        history: [ExerciseHistoryEntry],
        reps: Int,
        rir: Int,
        bodyweightKg: Double = 0
    ) -> Double? {
        let base = exercise.equipment == .bodyweight ? max(0, bodyweightKg) : 0
        guard let latest = history
            .filter({ $0.exerciseID == exercise.id && !$0.workingSets.isEmpty })
            .max(by: { $0.date < $1.date }),
            let e1rm = latest.sessionOneRepMax(bodyweightKg: base)
        else { return nil }
        let total = load(forOneRepMax: e1rm, reps: reps, rir: rir)
        return max(0, roundToIncrement(total - base, increment: exercise.equipment.incrementKg))
    }
}
