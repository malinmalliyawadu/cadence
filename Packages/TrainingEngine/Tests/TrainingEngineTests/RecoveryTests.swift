import Foundation
import Testing
@testable import TrainingEngine

@Suite("Recovery")
struct RecoveryTests {
    let calendar = Calendar(identifier: .gregorian)
    /// Mid-morning, so last night's sleep is in and today's resting heart rate is not.
    let now = Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)).addingTimeInterval(9 * 3600)

    func day(_ n: Int, hour: Double = 4) -> Date {
        calendar.startOfDay(for: now).addingTimeInterval(Double(-n) * 86_400 + hour * 3600)
    }

    /// HRV around `ms` for the days in `range` back, two readings a night, swinging 20% night to
    /// night as watch SDNN does.
    func hrv(_ ms: Double, days range: ClosedRange<Int>) -> [RecoveryReadings.Reading] {
        range.flatMap { n in
            let wobble = n % 2 == 0 ? 1.2 : 0.83
            return [RecoveryReadings.Reading(date: day(n, hour: 2), value: ms * wobble), .init(date: day(n, hour: 5), value: ms * wobble)]
        }
    }

    func resting(_ bpm: Double, days range: ClosedRange<Int>) -> [RecoveryReadings.Reading] {
        range.map { RecoveryReadings.Reading(date: day($0, hour: 12), value: bpm + Double($0 % 3) - 1) }
    }

    /// A night of `hours` asleep ending at 6:30 on the morning `n` days back.
    func night(_ n: Int, hours: Double) -> DateInterval {
        let end = day(n, hour: 6.5)
        return DateInterval(start: end.addingTimeInterval(-hours * 3600), end: end)
    }

    var usualReadings: RecoveryReadings {
        RecoveryReadings(
            hrv: hrv(60, days: 0...60),
            restingHeartRate: resting(50, days: 1...33),
            sleep: (0...31).map { night($0, hours: 7.5) }
        )
    }

    @Test("Nothing from the watch means no verdict and no change")
    func noData() {
        let status = RecoveryAnalysis.status(from: RecoveryReadings(), asOf: now, calendar: calendar)
        #expect(status.level == nil)
        #expect(status.loadMultiplier == 1)
        #expect(status.hrv == nil && status.restingHeartRate == nil && status.sleep == nil)
    }

    @Test("A few days of HRV are shown but not judged until there is a baseline")
    func hrvWithoutBaseline() {
        let status = RecoveryAnalysis.status(from: RecoveryReadings(hrv: hrv(55, days: 0...5)), asOf: now, calendar: calendar)
        #expect(status.hrv?.baseline == nil)
        #expect(status.hrv?.current != nil)
        #expect(status.level == nil)
    }

    @Test("Usual HRV, resting heart rate and sleep read as recovered")
    func recovered() {
        let status = RecoveryAnalysis.status(from: usualReadings, asOf: now, calendar: calendar)
        #expect(status.level == .recovered)
        #expect(status.loadMultiplier == 1)
        #expect(status.reason == nil)
        let range = status.hrv!.normalRange!
        #expect(range.contains(status.hrv!.current))
        #expect(abs(status.hrv!.baseline! - 60) < 3)
        #expect(abs(status.restingHeartRate!.baseline! - 50) < 1)
    }

    @Test("A week of HRV under the normal range trims lifts")
    func hrvDown() {
        var readings = usualReadings
        readings.hrv = hrv(60, days: 7...60) + hrv(48, days: 0...6)
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.hrv?.points == 2)
        #expect(status.level == .low)
        #expect(status.loadMultiplier == 0.95)
        #expect(status.headline(.trimmed) == "HRV is below your normal range. Today's lifts are 5% lighter.")
        #expect(status.headline(.started) == "HRV is below your normal range. Your session had started, so its loads stand. Ease off if the sets feel heavy.")
        #expect(status.headline(.none) == "HRV is below your normal range. Keep today's training easy.")
    }

    @Test("One bad night of HRV does not move the 7-day average out of range")
    func oneBadNight() {
        var readings = usualReadings
        readings.hrv = hrv(60, days: 1...60) + hrv(40, days: 0...0)
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.hrv?.points == 0)
        #expect(status.level == .recovered)
    }

    @Test("Resting heart rate counts 1 at 3 bpm up and 2 at 5")
    func restingUp() {
        var readings = usualReadings
        readings.restingHeartRate = resting(50, days: 3...33) + [.init(date: day(1, hour: 12), value: 53.5), .init(date: day(2, hour: 12), value: 53.5)]
        #expect(RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar).restingHeartRate?.points == 1)

        readings.restingHeartRate = resting(50, days: 3...33) + [.init(date: day(1, hour: 12), value: 56), .init(date: day(2, hour: 12), value: 56)]
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.restingHeartRate?.points == 2)
        #expect(status.restingHeartRate?.flag == "resting heart rate is up 6 bpm")
        #expect(status.level == .low)
    }

    @Test("HRV down with resting heart rate up is poor, and the headline names both")
    func poor() {
        var readings = usualReadings
        readings.hrv = hrv(60, days: 7...60) + hrv(45, days: 0...6)
        readings.restingHeartRate = resting(50, days: 3...33) + [.init(date: day(1, hour: 12), value: 57), .init(date: day(2, hour: 12), value: 57)]
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.level == .poor)
        #expect(status.loadMultiplier == 0.9)
        #expect(status.reason == "HRV is below your normal range and resting heart rate is up 7 bpm")
        #expect(status.headline(.trimmed).hasSuffix("Today's lifts are 10% lighter."))
    }

    @Test("Short sleep alone is a flag, not a cut")
    func shortSleep() {
        var readings = usualReadings
        readings.sleep = (1...31).map { night($0, hours: 7.5) } + [night(0, hours: 5)]
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.sleep?.points == 1)
        #expect(status.level == .fair)
        #expect(status.loadMultiplier == 1)
        #expect(status.headline(.trimmed) == "Sleep was short, but not enough to change today. Train as planned.")
    }

    @Test("Three nights an hour under the usual is a flag even when each clears 6 hours")
    func sleepDebt() {
        var readings = usualReadings
        readings.sleep = (3...31).map { night($0, hours: 8) } + (0...2).map { night($0, hours: 6.5) }
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.sleep?.flag == "you have slept an hour less than usual")
    }

    @Test("Sleep recorded twice, by the watch and the phone, is counted once")
    func overlappingSleep() {
        let watch = DateInterval(start: day(0, hour: -1), end: day(0, hour: 6))
        let phone = DateInterval(start: day(0, hour: 0), end: day(0, hour: 7))
        let nights = RecoveryAnalysis.nightlySleepHours([watch, phone], calendar: calendar)
        #expect(nights[calendar.startOfDay(for: now)] == 8)
    }

    @Test("A night that starts before midnight belongs to the morning it ends on")
    func nightKey() {
        let nights = RecoveryAnalysis.nightlySleepHours([DateInterval(start: day(1, hour: 22.5), end: day(0, hour: 6.5))], calendar: calendar)
        #expect(nights.keys.first == calendar.startOfDay(for: now))
    }

    @Test("No sleep recorded last night means no sleep signal, not zero hours")
    func watchOffOvernight() {
        var readings = usualReadings
        readings.sleep = (1...31).map { night($0, hours: 7.5) }
        let status = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)
        #expect(status.sleep == nil)
        #expect(status.level == .recovered)
    }

    @Test("Readiness takes the lower of load and recovery, and says why when recovery decides")
    func readinessCombines() {
        let steady = (0..<84).map { LoadEntry(date: day($0), modality: .strength, load: 300) }
        let snapshot = LoadAnalysis.snapshot(entries: steady, asOf: now, calendar: calendar)
        var readings = usualReadings
        readings.hrv = hrv(60, days: 7...60) + hrv(48, days: 0...6)
        let recovery = RecoveryAnalysis.status(from: readings, asOf: now, calendar: calendar)

        let readiness = Readiness.from(snapshot, recovery: recovery)
        #expect(readiness.loadMultiplier == 0.95)
        #expect(readiness.setReduction == 0)
        #expect(readiness.weeklyLoadFactor == Readiness.from(snapshot).weeklyLoadFactor)
        #expect(readiness.cutReason == "HRV is below your normal range")

        var spike = (7..<84).map { LoadEntry(date: day($0), modality: .running, load: 200) }
        spike += (0..<7).map { LoadEntry(date: day($0), modality: .running, load: 600) }
        let loaded = Readiness.from(LoadAnalysis.snapshot(entries: spike, asOf: now, calendar: calendar), recovery: recovery)
        #expect(loaded.loadMultiplier == 0.9)
        #expect(loaded.cutReason == nil)
    }

    @Test("A recovery cut explains itself in the movement's rationale")
    func progressionRationale() {
        let press = ExerciseLibrary.exercise(id: "bb-bench")!
        let history = [ExerciseHistoryEntry(exerciseID: press.id, date: day(7), targetReps: 6...8, targetRIR: 2,
                                            sets: [PerformedSet(weightKg: 80, reps: 6, rir: 2)])]
        let result = Progression.nextLoad(for: press, history: history, repRange: 6...8, targetRIR: 2,
                                          readiness: 0.9, readinessReason: "HRV is below your normal range")
        #expect(result.decision == .readinessCut)
        #expect(result.rationale == "HRV is below your normal range, so this is 10% lighter than you have earned. Keep the RIR honest.")
        #expect(result.weightKg! < 80)

        let first = Progression.nextLoad(for: press, history: [], repRange: 6...8, targetRIR: 2,
                                         readiness: 0.95, readinessReason: "HRV is below your normal range")
        #expect(first.weightKg == 37.5)
        #expect(first.rationale.hasPrefix("First time on this movement, and HRV is below your normal range, so this starts 5% lighter."))
        let loaded = Progression.nextLoad(for: press, history: [], repRange: 6...8, targetRIR: 2, readiness: 0.9)
        #expect(loaded.rationale.hasPrefix("First time on this movement, and training load is running high this week, so this starts 10% lighter."))
    }
}
