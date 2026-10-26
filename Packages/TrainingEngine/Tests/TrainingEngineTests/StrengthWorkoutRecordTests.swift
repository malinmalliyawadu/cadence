import Foundation
import Testing
@testable import TrainingEngine

@Suite("Strength workout record")
struct StrengthWorkoutRecordTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func minutes(_ n: Double) -> Date { start.addingTimeInterval(n * 60) }

    @Test("A session logged as it happened spans the first set to the last")
    func liveLogging() throws {
        let times = [minutes(40), minutes(0), minutes(12), minutes(25)]
        let interval = try #require(StrengthWorkoutRecord.interval(setTimes: times, firstSetSeconds: 30, plannedMinutes: 55))
        #expect(interval.start == start.addingTimeInterval(-30))
        #expect(interval.end == minutes(40))
    }

    @Test("Sets logged after the fact take the planned length, ending at the last set")
    func loggedAfterwards() throws {
        let times = [minutes(0), minutes(0.5), minutes(1)]
        let interval = try #require(StrengthWorkoutRecord.interval(setTimes: times, firstSetSeconds: 30, plannedMinutes: 50))
        #expect(interval.end == minutes(1))
        #expect(interval.duration == 50 * 60)
    }

    @Test("No logged sets, no workout")
    func nothingLogged() {
        #expect(StrengthWorkoutRecord.interval(setTimes: [], firstSetSeconds: 30, plannedMinutes: 50) == nil)
    }

    @Test("Effort moves the MET between moderate and vigorous lifting")
    func metRange() {
        #expect(StrengthWorkoutRecord.met(rpe: 3) == 3.5)
        #expect(StrengthWorkoutRecord.met(rpe: 6.5) == 4.75)
        #expect(StrengthWorkoutRecord.met(rpe: 9) == 6)
    }

    @Test("An hour of hard lifting at 80 kg is 400 active kilocalories")
    func energy() {
        #expect(StrengthWorkoutRecord.activeKilocalories(bodyweightKg: 80, minutes: 60, rpe: 8) == 400)
        #expect(StrengthWorkoutRecord.activeKilocalories(bodyweightKg: 80, minutes: 0, rpe: 8) == 0)
    }
}
