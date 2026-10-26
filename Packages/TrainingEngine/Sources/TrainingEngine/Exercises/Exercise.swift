import Foundation

public enum MuscleGroup: String, Codable, Sendable, CaseIterable, Hashable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves, core

    public var half: BodyHalf {
        switch self {
        case .chest, .back, .shoulders, .biceps, .triceps: .upper
        case .quads, .hamstrings, .glutes, .calves, .core: .lower
        }
    }

    public var displayName: String { rawValue.capitalized }
}

public enum MovementPattern: String, Codable, Sendable, CaseIterable, Hashable {
    case horizontalPush, horizontalPull, verticalPush, verticalPull
    case squat, hinge, lunge, hipExtension
    case elbowFlexion, elbowExtension, lateralRaise
    case calfRaise, coreBrace
}

public enum Equipment: String, Codable, Sendable, CaseIterable, Hashable {
    case barbell, dumbbell, cable, machine, bodyweight, kettlebell

    /// Smallest sensible jump in load for this equipment, in kilograms.
    public var incrementKg: Double {
        switch self {
        case .barbell: 2.5
        case .dumbbell: 2.0      // per hand, so 1 kg plates each side
        case .cable, .machine: 2.5
        case .kettlebell: 4.0
        case .bodyweight: 2.5    // added weight via belt or vest
        }
    }
}

/// How much of the session an exercise carries.
public enum ExerciseRole: String, Codable, Sendable, CaseIterable, Hashable {
    case compound     // multi-joint, heavy, first in the session
    case accessory    // multi-joint but lighter or unilateral
    case isolation    // single joint, pump work
}

public struct Exercise: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let pattern: MovementPattern
    public let primary: MuscleGroup
    public let secondary: [MuscleGroup]
    public let equipment: Equipment
    public let role: ExerciseRole
    public let unilateral: Bool
    /// Conservative load for an athlete with no history on this movement, in kilograms.
    public let startingWeightKg: Double
    /// Seconds for one rep at working tempo, used to estimate session duration.
    public let secondsPerRep: Double

    public init(
        id: String,
        name: String,
        pattern: MovementPattern,
        primary: MuscleGroup,
        secondary: [MuscleGroup] = [],
        equipment: Equipment,
        role: ExerciseRole,
        unilateral: Bool = false,
        startingWeightKg: Double,
        secondsPerRep: Double = 3
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.role = role
        self.unilateral = unilateral
        self.startingWeightKg = startingWeightKg
        self.secondsPerRep = secondsPerRep
    }

    public var half: BodyHalf { primary.half }
    public var muscles: [MuscleGroup] { [primary] + secondary }

    public func trains(_ group: MuscleGroup) -> Bool { muscles.contains(group) }
}
