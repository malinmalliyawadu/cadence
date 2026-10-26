import Foundation

/// Inputs for one generated strength session.
public struct StrengthSessionRequest: Sendable {
    public var half: BodyHalf
    public var focus: FocusArea
    public var availableEquipment: Set<Equipment>
    /// Exercise IDs used in the most recent session of the same half. The generator
    /// avoids repeating accessories so a four-week block does not feel like one workout.
    public var recentExerciseIDs: Set<String>
    public var history: [ExerciseHistoryEntry]
    /// Load-management multiplier from `ReadinessPolicy`. 1.0 means train as earned.
    public var readiness: Double
    /// Sets removed from every non-isolation movement when load is running high.
    public var setReduction: Int
    /// Any stable integer. Changing it rotates accessory choices.
    public var variationSeed: Int

    public init(
        half: BodyHalf,
        focus: FocusArea,
        availableEquipment: Set<Equipment> = Set(Equipment.allCases),
        recentExerciseIDs: Set<String> = [],
        history: [ExerciseHistoryEntry] = [],
        readiness: Double = 1.0,
        setReduction: Int = 0,
        variationSeed: Int = 0
    ) {
        precondition(focus.half == half, "Focus \(focus) does not belong to the \(half) half")
        self.half = half
        self.focus = focus
        self.availableEquipment = availableEquipment
        self.recentExerciseIDs = recentExerciseIDs
        self.history = history
        self.readiness = readiness
        self.setReduction = setReduction
        self.variationSeed = variationSeed
    }
}

public struct GeneratedStrengthSession: Sendable, Hashable {
    public let half: BodyHalf
    public let focus: FocusArea
    public let prescriptions: [ExercisePrescription]

    public var estimatedMinutes: Double {
        8 + prescriptions.map(\.estimatedMinutes).reduce(0, +) // 8 minutes of warm-up
    }

    public var meanTargetRIR: Double {
        guard !prescriptions.isEmpty else { return 2 }
        return Double(prescriptions.map(\.targetRIR).reduce(0, +)) / Double(prescriptions.count)
    }

    /// Foster session-RPE load in arbitrary units (RPE x minutes).
    public var estimatedLoad: Double {
        TrainingLoad.strengthSessionRPE(meanRIR: meanTargetRIR) * estimatedMinutes
    }
}

/// Builds an upper or lower session around a focus area.
///
/// Each session is six slots. The focus gets the opener, a second compound or heavy
/// accessory, and the first isolation slot, each with an extra set. The rest of the
/// half is covered by an antagonist compound and a balancing accessory so nothing is
/// neglected across the week. Selection is deterministic for a given request.
public enum WorkoutGenerator {
    private struct Slot {
        enum Target { case focus, antagonist, balance, finisher }
        let target: Target
        let roles: [ExerciseRole]
        let scheme: SetScheme
    }

    public struct SetScheme: Sendable, Hashable {
        public let sets: Int
        public let reps: ClosedRange<Int>
        public let rir: Int
        public init(sets: Int, reps: ClosedRange<Int>, rir: Int) {
            self.sets = sets
            self.reps = reps
            self.rir = rir
        }
    }

    public static let openerScheme = SetScheme(sets: 4, reps: 5...8, rir: 2)
    public static let compoundScheme = SetScheme(sets: 3, reps: 6...8, rir: 2)
    public static let secondaryScheme = SetScheme(sets: 3, reps: 8...10, rir: 2)
    public static let accessoryScheme = SetScheme(sets: 3, reps: 10...12, rir: 2)
    public static let isolationScheme = SetScheme(sets: 3, reps: 12...15, rir: 1)
    public static let finisherScheme = SetScheme(sets: 2, reps: 12...15, rir: 1)

    private static let slots: [Slot] = [
        Slot(target: .focus, roles: [.compound], scheme: openerScheme),
        Slot(target: .antagonist, roles: [.compound], scheme: compoundScheme),
        Slot(target: .focus, roles: [.accessory, .compound], scheme: secondaryScheme),
        Slot(target: .balance, roles: [.accessory, .compound], scheme: accessoryScheme),
        Slot(target: .focus, roles: [.isolation], scheme: isolationScheme),
        Slot(target: .finisher, roles: [.isolation], scheme: finisherScheme),
    ]

    public static func generate(_ request: StrengthSessionRequest) -> GeneratedStrengthSession {
        let pool = ExerciseLibrary.exercises(for: request.half)
            .filter { request.availableEquipment.contains($0.equipment) }

        var chosen: [Exercise] = []
        var prescriptions: [ExercisePrescription] = []

        for (index, slot) in slots.enumerated() {
            guard let exercise = pick(slot: slot, index: index, from: pool, chosen: chosen, request: request) else { continue }
            chosen.append(exercise)

            let isFocus = slot.target == .focus
            var sets = slot.scheme.sets + (isFocus && slot.roles.contains(.compound) && index > 0 ? 1 : 0)
            if exercise.role != .isolation { sets = max(2, sets - request.setReduction) }

            let progression = Progression.nextLoad(
                for: exercise,
                history: request.history,
                repRange: slot.scheme.reps,
                targetRIR: slot.scheme.rir,
                readiness: request.readiness
            )
            prescriptions.append(ExercisePrescription(
                exercise: exercise,
                sets: sets,
                repRange: slot.scheme.reps,
                targetRIR: slot.scheme.rir,
                weightKg: progression.weightKg,
                isFocus: isFocus,
                rationale: progression.rationale
            ))
        }

        return GeneratedStrengthSession(half: request.half, focus: request.focus, prescriptions: prescriptions)
    }

    // MARK: Selection

    private static func pick(slot: Slot, index: Int, from pool: [Exercise], chosen: [Exercise], request: StrengthSessionRequest) -> Exercise? {
        let focusMuscles = request.focus.muscles
        let coveredMuscles = Set(chosen.flatMap(\.muscles))
        let usedPatterns = Set(chosen.map(\.pattern))
        let opener = chosen.first

        var candidates = pool.filter { candidate in
            guard !chosen.contains(candidate), slot.roles.contains(candidate.role) else { return false }
            switch slot.target {
            case .focus:
                return focusMuscles.contains(candidate.primary)
            case .antagonist:
                guard let opener else { return true }
                return antagonistPatterns(of: opener.pattern).contains(candidate.pattern) && !focusMuscles.contains(candidate.primary)
            case .balance:
                let mainGroups = mainGroups(for: request.half)
                let uncovered = mainGroups.subtracting(coveredMuscles).subtracting(focusMuscles)
                if uncovered.isEmpty { return !focusMuscles.contains(candidate.primary) }
                return uncovered.contains(candidate.primary)
            case .finisher:
                let finisherGroups = finisherGroups(for: request.half, focus: request.focus)
                return finisherGroups.contains(candidate.primary) && !focusMuscles.contains(candidate.primary)
            }
        }

        if candidates.isEmpty {
            // Relax the muscle constraint but keep the role, so the session is still six movements.
            // A focus slot may fall back to a movement that hits the focus as a secondary muscle.
            candidates = pool.filter { candidate in
                guard !chosen.contains(candidate), slot.roles.contains(candidate.role) else { return false }
                return slot.target != .focus || !focusMuscles.isDisjoint(with: candidate.muscles)
            }
        }
        guard !candidates.isEmpty else { return nil }

        // Opener: honour the focus's preferred openers first.
        if index == 0 {
            for id in request.focus.preferredOpeners {
                if let preferred = candidates.first(where: { $0.id == id }) { return preferred }
            }
        }

        // Score: avoid repeating last session, avoid repeating a pattern already in this session,
        // prefer the first role listed for the slot. Ties rotate with the variation seed.
        let ranked = candidates.enumerated().map { offset, exercise -> (Exercise, Double) in
            var score = 0.0
            if request.recentExerciseIDs.contains(exercise.id) { score -= 10 }
            if usedPatterns.contains(exercise.pattern) { score -= 4 }
            if let roleIndex = slot.roles.firstIndex(of: exercise.role) { score -= Double(roleIndex) * 2 }
            if slot.target == .focus, exercise.unilateral { score += 1 } // unilateral focus work is a feature, not a fallback
            score += Double((offset + request.variationSeed) % candidates.count) * 0.01 // deterministic rotation
            return (exercise, score)
        }
        return ranked.max { $0.1 < $1.1 }?.0
    }

    private static func antagonistPatterns(of pattern: MovementPattern) -> Set<MovementPattern> {
        switch pattern {
        case .horizontalPush: [.horizontalPull, .verticalPull]
        case .horizontalPull: [.horizontalPush, .verticalPush]
        case .verticalPush: [.verticalPull, .horizontalPull]
        case .verticalPull: [.verticalPush, .horizontalPush]
        case .squat, .lunge: [.hinge, .hipExtension]
        case .hinge, .hipExtension: [.squat, .lunge]
        case .elbowFlexion: [.elbowExtension, .horizontalPush]
        case .elbowExtension: [.elbowFlexion, .horizontalPull]
        case .lateralRaise, .calfRaise, .coreBrace: []
        }
    }

    private static func mainGroups(for half: BodyHalf) -> Set<MuscleGroup> {
        switch half {
        case .upper: [.chest, .back, .shoulders]
        case .lower: [.quads, .hamstrings, .glutes]
        }
    }

    private static func finisherGroups(for half: BodyHalf, focus: FocusArea) -> Set<MuscleGroup> {
        switch half {
        case .upper: [.biceps, .triceps, .shoulders]
        case .lower: [.calves, .core]
        }
    }
}
