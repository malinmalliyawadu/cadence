import Foundation
import Testing
@testable import TrainingEngine

@Suite("Exercise trends")
struct ExerciseTrendTests {
    let bench = ExerciseLibrary.exercise(id: "bb-bench")!
    let dip = ExerciseLibrary.exercise(id: "dip")!
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let week: TimeInterval = 7 * 86_400

    func entry(_ exercise: Exercise, week index: Int, weight: Double, reps: Int = 6, rir: Int? = 2, sets: Int = 3) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            exerciseID: exercise.id,
            date: start.addingTimeInterval(Double(index) * week),
            targetReps: 5...8,
            targetRIR: 2,
            sets: Array(repeating: PerformedSet(weightKg: weight, reps: reps), count: sets - 1) + [PerformedSet(weightKg: weight, reps: reps, rir: rir)]
        )
    }

    @Test("Points follow the movement oldest first, one per session")
    func pointsInOrder() {
        let history = [entry(bench, week: 2, weight: 85), entry(bench, week: 0, weight: 80), entry(dip, week: 1, weight: 10)]
        let points = ExerciseTrend.points(for: bench, history: history)
        #expect(points.map(\.date) == [start, start.addingTimeInterval(2 * week)])
        #expect(points[0].oneRepMax == Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 2))
        #expect(points[0].volumeKg == 80 * 6 * 3)
        #expect(points[0].workingSets == 3)
    }

    @Test("A best beats every earlier session, and the first sets none")
    func bests() {
        let history = [80.0, 85, 82.5, 85, 87.5].enumerated().map { entry(bench, week: $0.offset, weight: $0.element) }
        #expect(ExerciseTrend.points(for: bench, history: history).map(\.isBest) == [false, true, false, false, true])
    }

    @Test("The top set is the heaviest, then the one with most reps")
    func topSet() {
        let mixed = ExerciseHistoryEntry(exerciseID: bench.id, date: start, targetReps: 5...8, targetRIR: 2, sets: [
            PerformedSet(weightKg: 80, reps: 8), PerformedSet(weightKg: 85, reps: 5), PerformedSet(weightKg: 85, reps: 6, rir: 1),
        ])
        #expect(ExerciseTrend.points(for: bench, history: [mixed]).first?.topSet == PerformedSet(weightKg: 85, reps: 6, rir: 1))
    }

    @Test("Bodyweight movements count bodyweight in strength and volume, not in the top set")
    func bodyweight() {
        let point = ExerciseTrend.points(for: dip, history: [entry(dip, week: 0, weight: 0, reps: 10)], bodyweightKg: 80).first
        #expect(point?.oneRepMax == Progression.estimatedOneRepMax(weightKg: 80, reps: 10, rir: 2))
        #expect(point?.volumeKg == Double(80 * 10 * 3))
        #expect(point?.topSet.weightKg == 0)
    }

    @Test("Imports with no RIR are read at the target, as progression reads them")
    func unrated() {
        let point = ExerciseTrend.points(for: bench, history: [entry(bench, week: 0, weight: 80, rir: nil)]).first
        #expect(point?.oneRepMax == Progression.estimatedOneRepMax(weightKg: 80, reps: 6, rir: 2))
    }

    @Test("A steady climb reads as climbing, with its change and weekly slope")
    func climbing() throws {
        let history = (0..<6).map { entry(bench, week: $0, weight: 80 + 2.5 * Double($0)) }
        let summary = try #require(ExerciseTrend.summary(of: ExerciseTrend.points(for: bench, history: history), metric: .topSet))
        #expect(summary.change == 12.5)
        #expect(abs(summary.changeFraction - 12.5 / 80) < 0.0001)
        #expect(abs((summary.perWeek ?? 0) - 2.5) < 0.0001)
        #expect(summary.direction == .climbing)
        #expect(summary.sessions == 6)
    }

    @Test("Noise around a level holds, and a slide slips")
    func holdingAndSlipping() {
        let flat = [80.0, 82.5, 80, 82.5, 80, 82.5].enumerated().map { entry(bench, week: $0.offset, weight: $0.element) }
        let sliding = [90.0, 87.5, 85, 82.5].enumerated().map { entry(bench, week: $0.offset, weight: $0.element) }
        #expect(ExerciseTrend.summary(of: ExerciseTrend.points(for: bench, history: flat), metric: .oneRepMax)?.direction == .holding)
        #expect(ExerciseTrend.summary(of: ExerciseTrend.points(for: bench, history: sliding), metric: .oneRepMax)?.direction == .slipping)
    }

    @Test("The window starts where asked, and two sessions give a change but no direction")
    func window() throws {
        let history = (0..<5).map { entry(bench, week: $0, weight: 80 + 2.5 * Double($0)) }
        let points = ExerciseTrend.points(for: bench, history: history)
        let summary = try #require(ExerciseTrend.summary(of: points, metric: .topSet, since: start.addingTimeInterval(3 * week)))
        #expect(summary.sessions == 2)
        #expect(summary.change == 2.5)
        #expect(summary.direction == nil)
        #expect(ExerciseTrend.summary(of: points, metric: .topSet, since: start.addingTimeInterval(4 * week)) == nil)
    }

    @Test("Records go to the session that set them first")
    func records() {
        let history = [
            entry(bench, week: 0, weight: 85, reps: 5, sets: 5),
            entry(bench, week: 1, weight: 85, reps: 5, sets: 3),
            entry(bench, week: 2, weight: 80, reps: 8),
        ]
        let records = ExerciseTrend.records(of: ExerciseTrend.points(for: bench, history: history))
        #expect(records.heaviestSet?.date == start)
        #expect(records.mostVolume?.date == start)
        #expect(records.bestOneRepMax?.date == start.addingTimeInterval(2 * week))
        #expect(ExerciseTrend.records(of: []).bestOneRepMax == nil)
    }
}
