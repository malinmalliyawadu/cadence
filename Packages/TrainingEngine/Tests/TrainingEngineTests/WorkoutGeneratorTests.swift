import Foundation
import Testing
@testable import TrainingEngine

@Suite("Workout generator")
struct WorkoutGeneratorTests {
    @Test("Every focus produces a six-movement session that opens on its preferred compound", arguments: FocusArea.allCases)
    func opener(focus: FocusArea) {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: focus.half, focus: focus))
        #expect(session.prescriptions.count == 6)
        #expect(session.prescriptions.first?.exercise.id == focus.preferredOpeners.first)
        #expect(session.prescriptions.first?.isFocus == true)
        #expect(Set(session.prescriptions.map(\.exercise.id)).count == 6, "no repeated movements")
        #expect(session.prescriptions.allSatisfy { $0.exercise.half == focus.half })
    }

    @Test("Focus gets three of the six slots and the rest of the half is still covered", arguments: FocusArea.allCases)
    func coverage(focus: FocusArea) {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: focus.half, focus: focus))
        let focusCount = session.prescriptions.filter(\.isFocus).count
        #expect(focusCount == 3)
        let trained = Set(session.prescriptions.flatMap(\.exercise.muscles))
        let required: Set<MuscleGroup> = focus.half == .upper ? [.chest, .back, .shoulders] : [.quads, .hamstrings, .glutes]
        #expect(required.isSubset(of: trained), "\(focus) left out \(required.subtracting(trained))")
    }

    @Test("Second slot is an antagonist of the opener")
    func antagonist() {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .chest))
        let second = session.prescriptions[1].exercise
        #expect([.horizontalPull, .verticalPull].contains(second.pattern))
        let lower = WorkoutGenerator.generate(StrengthSessionRequest(half: .lower, focus: .quads))
        #expect([.hinge, .hipExtension].contains(lower.prescriptions[1].exercise.pattern))
    }

    @Test("Focus compounds carry an extra set")
    func focusVolume() {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .back))
        let secondary = session.prescriptions[2]
        #expect(secondary.isFocus)
        #expect(secondary.sets == WorkoutGenerator.secondaryScheme.sets + 1)
    }

    @Test("Set reduction trims compounds but never isolation work below two sets")
    func setReduction() {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .lower, focus: .glutes, setReduction: 1))
        let opener = session.prescriptions[0]
        #expect(opener.sets == WorkoutGenerator.openerScheme.sets - 1)
        #expect(session.prescriptions.allSatisfy { $0.sets >= 2 })
    }

    @Test("Equipment filter is respected")
    func equipment() {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .chest, availableEquipment: [.dumbbell, .cable, .bodyweight]))
        #expect(session.prescriptions.allSatisfy { $0.exercise.equipment != .barbell && $0.exercise.equipment != .machine })
        #expect(session.prescriptions.first?.exercise.id == "db-incline-press")
    }

    @Test("Recently used accessories rotate out")
    func variety() {
        let first = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .shoulders))
        let second = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .shoulders, recentExerciseIDs: Set(first.prescriptions.map(\.exercise.id))))
        let overlap = Set(first.prescriptions.map(\.exercise.id)).intersection(second.prescriptions.map(\.exercise.id))
        // The opener is pinned by design; everything else should move where the catalogue allows.
        #expect(overlap.count <= 2, "overlap was \(overlap)")
    }

    @Test("Generation is deterministic")
    func deterministic() {
        let a = WorkoutGenerator.generate(StrengthSessionRequest(half: .lower, focus: .posteriorChain, variationSeed: 3))
        let b = WorkoutGenerator.generate(StrengthSessionRequest(half: .lower, focus: .posteriorChain, variationSeed: 3))
        #expect(a == b)
    }

    @Test("History drives the prescribed load")
    func usesHistory() {
        let history = [ExerciseHistoryEntry(exerciseID: "bb-bench", date: .now.addingTimeInterval(-7 * 86_400), targetReps: 5...8, targetRIR: 2,
                                            sets: Array(repeating: PerformedSet(weightKg: 90, reps: 6, rir: 2), count: 4))]
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .chest, history: history))
        #expect(session.prescriptions[0].weightKg == 90)
    }

    @Test("Estimated duration is a realistic gym hour")
    func duration() {
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .chest))
        #expect(session.estimatedMinutes > 45 && session.estimatedMinutes < 90, "was \(session.estimatedMinutes)")
        #expect(session.estimatedLoad > 250 && session.estimatedLoad < 700, "was \(session.estimatedLoad)")
    }
}
