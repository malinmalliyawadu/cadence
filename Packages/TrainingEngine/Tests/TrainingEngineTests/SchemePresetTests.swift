import Foundation
import Testing
@testable import TrainingEngine

@Suite("Scheme presets")
struct SchemePresetTests {
    let rdl = ExerciseLibrary.exercise(id: "rdl")!
    let curl = ExerciseLibrary.exercise(id: "leg-curl")!

    func history(_ exercise: Exercise, weight: Double, reps: Int, rir: Int) -> [ExerciseHistoryEntry] {
        [ExerciseHistoryEntry(exerciseID: exercise.id, date: .now, targetReps: 6...8, targetRIR: 2,
                              sets: [PerformedSet(weightKg: weight, reps: reps), PerformedSet(weightKg: weight, reps: reps, rir: rir)])]
    }

    @Test("Fewer reps earns more weight, more reps less, from the same estimated max")
    func loadFollowsReps() {
        let past = history(rdl, weight: 80, reps: 8, rir: 2)
        let heavy = Progression.load(for: rdl, history: past, reps: 4, rir: 2)!
        let light = Progression.load(for: rdl, history: past, reps: 12, rir: 2)!
        #expect(heavy > 80)
        #expect(light < 80)
        #expect(heavy.truncatingRemainder(dividingBy: rdl.equipment.incrementKg) == 0)
    }

    @Test("No step cap: a deliberate change of scheme moves the weight as far as the maths says")
    func noCap() {
        let past = history(rdl, weight: 100, reps: 12, rir: 2)
        let heavy = Progression.load(for: rdl, history: past, reps: 4, rir: 2)!
        #expect(heavy - 100 > rdl.equipment.incrementKg * 2)
    }

    @Test("Without history there is nothing to work from")
    func noHistory() {
        #expect(Progression.load(for: rdl, history: [], reps: 5, rir: 2) == nil)
    }

    @Test("Presets fit the movement: no heavy fives on isolation, no pump work on compounds")
    func presetsByRole() {
        #expect(!SchemePreset.presets(for: curl.role).contains { $0.name == "Heavy" })
        #expect(!SchemePreset.presets(for: rdl.role).contains { $0.name == "Pump" })
        #expect(SchemePreset.presets(for: .compound).count >= 3)
    }
}
