import Foundation

/// Inputs for one generated strength session.
public struct StrengthSessionRequest: Sendable {
    /// Sessions logged per exercise ID, derived from `history`. Familiar movements are preferred.
    public var familiarity: [String: Int] {
        var counts: [String: Int] = [:]
        for entry in history where !entry.workingSets.isEmpty { counts[entry.exerciseID, default: 0] += 1 }
        return counts
    }

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
    /// Athlete bodyweight, used to progress dips, pull-ups and chin-ups.
    public var bodyweightKg: Double
    /// Exercise IDs the athlete wants in every session of this half, whatever the focus.
    /// They come on top of the six slots and are never picked for one. IDs from the other half are ignored.
    public var alwaysIncluded: [String]

    public init(
        half: BodyHalf,
        focus: FocusArea,
        availableEquipment: Set<Equipment> = Set(Equipment.allCases),
        recentExerciseIDs: Set<String> = [],
        history: [ExerciseHistoryEntry] = [],
        readiness: Double = 1.0,
        setReduction: Int = 0,
        variationSeed: Int = 0,
        bodyweightKg: Double = 0,
        alwaysIncluded: [String] = []
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
        self.bodyweightKg = bodyweightKg
        self.alwaysIncluded = alwaysIncluded
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
/// neglected across the week. Movements the athlete always wants are added on top, in
/// role order. Selection is deterministic for a given request.
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
        let added = alwaysIncluded(in: request)
        let pool = ExerciseLibrary.exercises(for: request.half)
            .filter { request.availableEquipment.contains($0.equipment) && !added.contains($0) }

        var chosen: [Exercise] = []
        var prescriptions: [ExercisePrescription] = []

        for (index, slot) in slots.enumerated() {
            guard let exercise = pick(slot: slot, index: index, from: pool, chosen: chosen, added: added, request: request) else { continue }
            chosen.append(exercise)

            let isFocus = slot.target == .focus
            var sets = slot.scheme.sets + (isFocus && slot.roles.contains(.compound) && index > 0 ? 1 : 0)
            if exercise.role != .isolation { sets = max(2, sets - request.setReduction) }

            let progression = Progression.nextLoad(
                for: exercise,
                history: request.history,
                repRange: slot.scheme.reps,
                targetRIR: slot.scheme.rir,
                readiness: request.readiness,
                bodyweightKg: request.bodyweightKg
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

        for exercise in added {
            let index = insertionIndex(for: exercise.role, in: prescriptions.map(\.exercise.role))
            prescriptions.insert(prescription(adding: exercise, for: request), at: index)
        }

        return GeneratedStrengthSession(half: request.half, focus: request.focus, prescriptions: prescriptions)
    }

    // MARK: Always included

    /// The scheme for a movement added on top of the slots: what its role would get in a slot of its own.
    public static func addedScheme(for role: ExerciseRole) -> SetScheme {
        switch role {
        case .compound: compoundScheme
        case .accessory: accessoryScheme
        case .isolation: isolationScheme
        }
    }

    /// The prescription for an always-included movement, progressed from its own history like any slot.
    public static func prescription(adding exercise: Exercise, for request: StrengthSessionRequest) -> ExercisePrescription {
        let scheme = addedScheme(for: exercise.role)
        let sets = exercise.role == .isolation ? scheme.sets : max(2, scheme.sets - request.setReduction)
        let progression = Progression.nextLoad(
            for: exercise,
            history: request.history,
            repRange: scheme.reps,
            targetRIR: scheme.rir,
            readiness: request.readiness,
            bodyweightKg: request.bodyweightKg
        )
        return ExercisePrescription(
            exercise: exercise,
            sets: sets,
            repRange: scheme.reps,
            targetRIR: scheme.rir,
            weightKg: progression.weightKg,
            isFocus: false,
            rationale: progression.rationale
        )
    }

    /// Where a movement of `role` goes among movements of `roles`: before the first lighter one,
    /// so an added compound is not left until the end and an added isolation closes the session.
    public static func insertionIndex(for role: ExerciseRole, in roles: [ExerciseRole]) -> Int {
        let weight = ExerciseRole.allCases.firstIndex(of: role) ?? 0
        return roles.firstIndex { (ExerciseRole.allCases.firstIndex(of: $0) ?? 0) > weight } ?? roles.count
    }

    private static func alwaysIncluded(in request: StrengthSessionRequest) -> [Exercise] {
        var seen: Set<String> = []
        return request.alwaysIncluded
            .filter { seen.insert($0).inserted }
            .compactMap(ExerciseLibrary.exercise(id:))
            .filter { $0.half == request.half }
    }

    // MARK: Selection

    private static func pick(slot: Slot, index: Int, from pool: [Exercise], chosen: [Exercise], added: [Exercise], request: StrengthSessionRequest) -> Exercise? {
        let focusMuscles = request.focus.muscles
        let coveredMuscles = Set(chosen.flatMap(\.muscles))
        // Muscles an always-included movement already trains, so the balance and finisher slots look elsewhere.
        let addedMuscles = Set(added.map(\.primary))
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
                let uncovered = mainGroups.subtracting(coveredMuscles).subtracting(focusMuscles).subtracting(addedMuscles)
                if uncovered.isEmpty { return !focusMuscles.contains(candidate.primary) }
                return uncovered.contains(candidate.primary)
            case .finisher:
                let finisherGroups = finisherGroups(for: request.half, focus: request.focus)
                let open = finisherGroups.subtracting(addedMuscles)
                return (open.isEmpty ? finisherGroups : open).contains(candidate.primary) && !focusMuscles.contains(candidate.primary)
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

        // Opener: the focus's preferred openers, favouring one the athlete has actually logged.
        // Someone with 100 sets of Hammer Strength incline press and 3 of barbell bench should
        // open on the machine they know, not the textbook lift.
        if index == 0 {
            let familiarity = request.familiarity
            let preferred = request.focus.preferredOpeners.compactMap { id in candidates.first { $0.id == id } }
            if let known = preferred.filter({ familiarity[$0.id, default: 0] > 0 }).max(by: { familiarity[$0.id, default: 0] < familiarity[$1.id, default: 0] }) {
                return known
            }
            if let familiar = candidates.filter({ familiarity[$0.id, default: 0] >= 3 }).max(by: { familiarity[$0.id, default: 0] < familiarity[$1.id, default: 0] }) {
                return familiar
            }
            if let first = preferred.first { return first }
        }

        // Score: avoid repeating last session, avoid repeating a pattern already in this session,
        // prefer the first role listed for the slot. Ties rotate with the variation seed.
        let ranked = candidates.enumerated().map { offset, exercise -> (Exercise, Double) in
            var score = 0.0
            if request.recentExerciseIDs.contains(exercise.id) { score -= 10 }
            if let sessions = request.familiarity[exercise.id], sessions > 0 { score += min(6, 2 + Double(sessions) * 0.5) }
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
        case .kneeFlexion: [.kneeExtension, .squat]
        case .kneeExtension: [.kneeFlexion, .hinge]
        case .elbowFlexion: [.elbowExtension, .horizontalPush]
        case .elbowExtension: [.elbowFlexion, .horizontalPull]
        case .lateralRaise, .wristFlexion, .calfRaise, .coreBrace: []
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
