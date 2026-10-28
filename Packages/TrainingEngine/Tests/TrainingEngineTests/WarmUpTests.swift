import Foundation
import Testing
@testable import TrainingEngine

@Suite("Warm-up sets")
struct WarmUpTests {
    func ramp(_ id: String, at weight: Double?) -> [WarmUpSet] {
        WarmUp.sets(for: ExerciseLibrary.exercise(id: id)!, workingWeightKg: weight)
    }

    @Test("Presses, rows and machine or cable arm work take one set of 8 at about 60%, rounded down to the plate")
    func oneSet() {
        #expect(ramp("hs-chest-press", at: 45) == [WarmUpSet(weightKg: 25, reps: 8)])
        #expect(ramp("cable-curl", at: 25) == [WarmUpSet(weightKg: 15, reps: 8)])
        #expect(ramp("machine-fly", at: 70) == [WarmUpSet(weightKg: 40, reps: 8)])
        #expect(ramp("leg-extension", at: 60) == [WarmUpSet(weightKg: 35, reps: 8)])
        #expect(ramp("db-incline-press", at: 30) == [WarmUpSet(weightKg: 18, reps: 8)])
    }

    @Test("From 100 kg a second set of 3 closes the gap")
    func heavyLoads() {
        #expect(ramp("leg-press", at: 180) == [WarmUpSet(weightKg: 107.5, reps: 8), WarmUpSet(weightKg: 152.5, reps: 3)])
        #expect(ramp("leg-press", at: 97.5).count == 1)
    }

    @Test("Light work goes straight in", arguments: [
        "wrist-curl", "cable-wrist-curl", "reverse-curl", "lateral-raise", "cable-lateral-raise", "standing-calf-raise",
        "hip-abduction", "cable-kickback", "hammer-curl", "db-curl", "cable-crunch", "pull-up", "dip", "bulgarian-split-squat",
    ])
    func noWarmUp(id: String) {
        #expect(ramp(id, at: 40).isEmpty)
    }

    @Test("Nothing to ramp to, or too light to ramp, means no warm-up")
    func noWorkingWeight() {
        #expect(ramp("hs-chest-press", at: nil).isEmpty)
        #expect(ramp("hs-chest-press", at: 0).isEmpty)
        #expect(ramp("cable-curl", at: 2.5).isEmpty)
    }
}
