import Foundation
import Testing
@testable import TrainingEngine

@Suite("Rest timer")
struct RestTimerTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Heavy compounds rest longest, pump work least")
    func intervalByRoleAndRange() {
        #expect(RestInterval.seconds(for: .compound, repRange: 4...6) == 180)
        #expect(RestInterval.seconds(for: .compound, repRange: 6...10) == 150)
        #expect(RestInterval.seconds(for: .accessory, repRange: 8...12) == 105)
        #expect(RestInterval.seconds(for: .isolation, repRange: 10...15) == 75)
        #expect(RestInterval.seconds(for: .isolation, repRange: 15...20) == 60)
    }

    @Test("Session minutes count the same rest the clock does")
    func estimateUsesInterval() {
        let press = ExerciseLibrary.exercise(id: "hs-chest-press")!
        let prescription = ExercisePrescription(exercise: press, sets: 3, repRange: 6...10, targetRIR: 2, weightKg: 40, isFocus: false, rationale: "")
        #expect(prescription.estimatedMinutes == (10 * press.secondsPerRep + 150) * 3 / 60)
    }

    @Test("Remaining, progress and overtime follow the wall clock")
    func countdown() {
        let timer = RestTimer(startedAt: start, seconds: 120)
        #expect(timer.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(timer.progress(at: start.addingTimeInterval(30)) == 0.25)
        #expect(!timer.isOver(at: start.addingTimeInterval(119)))
        #expect(timer.isOver(at: start.addingTimeInterval(120)))
        #expect(timer.remaining(at: start.addingTimeInterval(200)) == 0)
        #expect(timer.overtime(at: start.addingTimeInterval(200)) == 80)
        #expect(timer.progress(at: start.addingTimeInterval(200)) == 1)
    }

    @Test("Adding rest extends the end, and after the end counts from now")
    func addRest() {
        let timer = RestTimer(startedAt: start, seconds: 90)
        #expect(timer.adjusted(by: 30, at: start.addingTimeInterval(10)).endsAt == start.addingTimeInterval(120))
        #expect(timer.adjusted(by: 30, at: start.addingTimeInterval(100)).endsAt == start.addingTimeInterval(130))
        #expect(timer.adjusted(by: 30, at: start).startedAt == start)
    }

    @Test("Taking rest away never ends it before now")
    func removeRest() {
        let timer = RestTimer(startedAt: start, seconds: 90)
        #expect(timer.adjusted(by: -30, at: start.addingTimeInterval(10)).endsAt == start.addingTimeInterval(60))
        let now = start.addingTimeInterval(80)
        let cut = timer.adjusted(by: -30, at: now)
        #expect(cut.endsAt == now)
        #expect(cut.isOver(at: now))
    }

    @Test("Survives a round trip through JSON, as the Live Activity carries it")
    func codable() throws {
        let timer = RestTimer(startedAt: start, seconds: 150).adjusted(by: 30, at: start)
        let decoded = try JSONDecoder().decode(RestTimer.self, from: JSONEncoder().encode(timer))
        #expect(decoded == timer)
    }
}
