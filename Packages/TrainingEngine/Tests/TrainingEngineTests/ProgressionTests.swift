import Foundation
import Testing
@testable import TrainingEngine

@Suite("RIR progression")
struct ProgressionTests {
    let bench = ExerciseLibrary.exercise(id: "bb-bench")!
    let day: TimeInterval = 86_400

    func entry(daysAgo: Int, weight: Double, reps: Int, rir: Int, targetRIR: Int = 2, targetReps: ClosedRange<Int> = 5...8, sets: Int = 4) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            exerciseID: bench.id,
            date: Date(timeIntervalSinceNow: -Double(daysAgo) * day),
            targetReps: targetReps,
            targetRIR: targetRIR,
            // Only the final set is rated, as the app logs it.
            sets: Array(repeating: PerformedSet(weightKg: weight, reps: reps), count: sets - 1) + [PerformedSet(weightKg: weight, reps: reps, rir: rir)]
        )
    }

    @Test("e1RM and its inverse round-trip")
    func roundTrip() {
        let e1rm = Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 2)
        #expect(abs(e1rm - 80 * (1 + 8.0 / 30)) < 0.001)
        let back = Progression.load(forOneRepMax: e1rm, reps: 6, rir: 2)
        #expect(abs(back - 80) < 0.001)
    }

    @Test("RIR counts as unperformed reps")
    func rirRaisesEstimate() {
        let hard = Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 0)
        let easy = Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 3)
        #expect(easy > hard)
    }

    @Test("No history starts conservatively from the catalogue")
    func start() {
        let result = Progression.nextLoad(for: bench, history: [], repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .start)
        #expect(result.weightKg == 40)
    }

    @Test("Bodyweight movements with no history ask the athlete to find a weight")
    func startBodyweight() {
        let pullUp = ExerciseLibrary.exercise(id: "pull-up")!
        let result = Progression.nextLoad(for: pullUp, history: [], repRange: 5...8, targetRIR: 2)
        #expect(result.weightKg == nil)
    }

    @Test("Too many reps in reserve adds load")
    func increase() {
        let history = [entry(daysAgo: 7, weight: 80, reps: 6, rir: 4)]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .increase)
        #expect(result.weightKg! > 80)
        #expect(result.weightKg! <= 85, "never more than two increments at once")
        #expect(result.weightKg!.truncatingRemainder(dividingBy: 2.5) == 0)
    }

    @Test("Hitting the top of the range at target RIR adds load")
    func topOfRange() {
        let history = [entry(daysAgo: 7, weight: 80, reps: 8, rir: 2)]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .increase)
        #expect(result.weightKg! >= 82.5)
    }

    @Test("On target holds the weight")
    func hold() {
        let history = [entry(daysAgo: 7, weight: 80, reps: 6, rir: 2)]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .hold)
        #expect(result.weightKg == 80)
    }

    @Test("Grinding below target RIR backs off")
    func reduce() {
        let history = [entry(daysAgo: 7, weight: 80, reps: 5, rir: 0)]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .reduce)
        #expect(result.weightKg! < 80)
        #expect(result.weightKg! >= 75)
    }

    @Test("Three stalled sessions trigger a deload")
    func deload() {
        let history = [
            entry(daysAgo: 21, weight: 80, reps: 6, rir: 2),
            entry(daysAgo: 14, weight: 80, reps: 6, rir: 2),
            entry(daysAgo: 7, weight: 80, reps: 6, rir: 2),
        ]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .deload)
        #expect(result.weightKg! < 80 * 0.95)
    }

    @Test("Progress across three sessions is not a stall")
    func noFalseDeload() {
        let history = [
            entry(daysAgo: 21, weight: 75, reps: 6, rir: 2),
            entry(daysAgo: 14, weight: 77.5, reps: 6, rir: 2),
            entry(daysAgo: 7, weight: 80, reps: 6, rir: 2),
        ]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2)
        #expect(result.decision != .deload)
    }

    @Test("Low readiness cuts the load and says so")
    func readinessCut() {
        let history = [entry(daysAgo: 7, weight: 80, reps: 6, rir: 2)]
        let result = Progression.nextLoad(for: bench, history: history, repRange: 5...8, targetRIR: 2, readiness: 0.9)
        #expect(result.decision == .readinessCut)
        #expect(result.weightKg! < 80)
    }

    @Test("Bodyweight movements progress on bodyweight plus added load")
    func bodyweightProgression() {
        let pullUp = ExerciseLibrary.exercise(id: "pull-up")!
        // 5 strict pull-ups at +0 with 4 in reserve for an 80 kg athlete: strong, should add load.
        let history = [ExerciseHistoryEntry(exerciseID: pullUp.id, date: .now.addingTimeInterval(-7 * day), targetReps: 5...8, targetRIR: 2,
                                            sets: Array(repeating: PerformedSet(weightKg: 0, reps: 8, rir: 4), count: 4))]
        let result = Progression.nextLoad(for: pullUp, history: history, repRange: 5...8, targetRIR: 2, bodyweightKg: 80)
        #expect(result.decision == .increase)
        #expect(result.weightKg! > 0 && result.weightKg! <= 5)

        // Grinding at +0 can only go to zero, never negative.
        let weak = [ExerciseHistoryEntry(exerciseID: pullUp.id, date: .now.addingTimeInterval(-7 * day), targetReps: 5...8, targetRIR: 2,
                                         sets: Array(repeating: PerformedSet(weightKg: 0, reps: 5, rir: 0), count: 4))]
        let floor = Progression.nextLoad(for: pullUp, history: weak, repRange: 5...8, targetRIR: 2, bodyweightKg: 80)
        #expect(floor.weightKg == 0)
        #expect(floor.decision == .reduce)
    }

    @Test("Only this exercise's history is consulted")
    func ignoresOtherExercises() {
        let squatHistory = ExerciseHistoryEntry(exerciseID: "bb-back-squat", date: .now, targetReps: 5...8, targetRIR: 2, sets: [PerformedSet(weightKg: 120, reps: 6, rir: 2)])
        let result = Progression.nextLoad(for: bench, history: [squatHistory], repRange: 5...8, targetRIR: 2)
        #expect(result.decision == .start)
    }

    @Test("Where several sets are rated, session e1RM uses the median, not the best")
    func medianSet() {
        let entry = ExerciseHistoryEntry(exerciseID: bench.id, date: .now, targetReps: 5...8, targetRIR: 2, sets: [
            PerformedSet(weightKg: 80, reps: 8, rir: 4), // optimistic outlier
            PerformedSet(weightKg: 80, reps: 6, rir: 2),
            PerformedSet(weightKg: 80, reps: 6, rir: 2),
        ])
        #expect(abs(entry.sessionOneRepMax! - Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 2)) < 0.001)
    }

    @Test("Session e1RM and mean RIR come from the rated final set")
    func finalSetRated() {
        let entry = ExerciseHistoryEntry(exerciseID: bench.id, date: .now, targetReps: 5...8, targetRIR: 2, sets: [
            PerformedSet(weightKg: 80, reps: 8),
            PerformedSet(weightKg: 80, reps: 7),
            PerformedSet(weightKg: 80, reps: 6, rir: 1),
        ])
        #expect(entry.meanRIR == 1)
        #expect(abs(entry.sessionOneRepMax! - Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 1)) < 0.001)
    }

    @Test("With no rated set, the last working set is assumed to land on the target")
    func noSetRated() {
        let entry = ExerciseHistoryEntry(exerciseID: bench.id, date: .now, targetReps: 5...8, targetRIR: 2, sets: [
            PerformedSet(weightKg: 80, reps: 8),
            PerformedSet(weightKg: 80, reps: 6),
        ])
        #expect(entry.meanRIR == 2)
        #expect(abs(entry.sessionOneRepMax! - Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 2)) < 0.001)
        let result = Progression.nextLoad(for: bench, history: [entry], repRange: 5...8, targetRIR: 2)
        #expect(result.decision != .start)
    }
}
