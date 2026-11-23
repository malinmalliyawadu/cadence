import Foundation
import Testing
@testable import TrainingEngine

@Suite("Race predictions")
struct RacePredictionTests {
    let day: TimeInterval = 86_400

    // From the athlete's export: a 10 km in 51:50 and a 30 km long run in 3:20:29.
    var runs: [RunEffort] {
        [
            RunEffort(date: .now.addingTimeInterval(-13 * day), distanceKm: 10.02, minutes: 51.83),
            RunEffort(date: .now.addingTimeInterval(-16 * day), distanceKm: 30.02, minutes: 200.48),
        ]
    }

    @Test("A 20 minute 5 km takes a VDOT of about 50")
    func goalFitness() {
        let goal = RunGoal(distance: .fiveK, minutes: 20)
        #expect(abs(goal.vdot - 49.8) < 0.1)
        #expect(goal.pace == 240)
    }

    /// Daniels' table for VDOT 50, in seconds, with how close the curves land.
    static let table: [(RaceDistance, Double, Double)] = [
        (.fiveK, 1197, 9),
        (.tenK, 2481, 15),
        (.half, 5495, 36),
        (.marathon, 11449, 90),
    ]

    @Test("Predictions match Daniels' table for VDOT 50")
    func danielsTable() {
        for (distance, seconds, tolerance) in Self.table {
            let predicted = RunPacing.predictedMinutes(distanceKm: distance.kilometres, vdot: 50) * 60
            #expect(abs(predicted - seconds) < tolerance, "\(distance.displayName): \(predicted)")
        }
    }

    @Test("A prediction run back through the curves gives the same fitness")
    func roundTrip() {
        for vdot in stride(from: 30.0, through: 70, by: 5) {
            let minutes = RunPacing.predictedMinutes(distanceKm: 5, vdot: vdot)
            #expect(abs(RunPacing.rawVDOT(distanceKm: 5, minutes: minutes) - vdot) < 0.001)
        }
    }

    @Test("The athlete's 10 km predicts a 5 km just under 25 minutes, about five off a 20 minute goal")
    func athleteGap() {
        let outlook = RaceOutlook.evaluate(runs: runs, goal: RunGoal(distance: .fiveK, minutes: 20))
        let fiveK = outlook.predictedMinutes(for: .fiveK)!
        #expect(fiveK > 24.5 && fiveK < 25.2)
        #expect(abs(outlook.goalGap! - (fiveK - 20)) < 0.001)
        #expect(!outlook.goalIsMet)
        // Longer races are slower per kilometre.
        let paces = RaceDistance.allCases.map { outlook.predictedMinutes(for: $0)! / $0.kilometres }
        #expect(paces == paces.sorted())
    }

    @Test("A goal the athlete already runs is met")
    func met() {
        let outlook = RaceOutlook.evaluate(runs: runs, goal: RunGoal(distance: .fiveK, minutes: 26))
        #expect(outlook.goalIsMet)
        #expect(outlook.projectedDate == nil)
    }

    @Test("No runs, no predictions")
    func empty() {
        let outlook = RaceOutlook.evaluate(runs: [], goal: RunGoal(distance: .fiveK, minutes: 20))
        #expect(outlook.vdot == nil)
        #expect(outlook.predictedMinutes(for: .fiveK) == nil)
        #expect(outlook.goalGap == nil)
        #expect(outlook.history.isEmpty)
    }

    /// A 5 km a week for `weeks` weeks, `secondsFaster` quicker each week, the latest today.
    func improving(weeks: Int, from minutes: Double, secondsFaster: Double) -> [RunEffort] {
        (0..<weeks).map { week in
            let back = Double(weeks - 1 - week)
            return RunEffort(date: .now.addingTimeInterval(-back * 7 * day), distanceKm: 5, minutes: minutes - Double(week) * secondsFaster / 60)
        }
    }

    @Test("A steadily rising trend projects a date for the goal")
    func projection() {
        let runs = improving(weeks: 14, from: 26, secondsFaster: 10)
        let start = RunPacing.fitness(from: runs, asOf: .now.addingTimeInterval(-8 * 7 * day))!
        let outlook = RaceOutlook.evaluate(runs: runs, goal: RunGoal(distance: .fiveK, minutes: 20), goalStartVDOT: start)
        let slope = outlook.vdotPerWeek!
        #expect(slope > RaceOutlook.trendThreshold)
        let date = outlook.projectedDate!
        let expectedWeeks = (outlook.goal!.vdot - outlook.vdot!) / slope
        #expect(abs(date.timeIntervalSinceNow / (7 * day) - expectedWeeks) < 0.01)
        #expect(outlook.goalProgress! > 0 && outlook.goalProgress! < 1)
    }

    @Test("Progress runs from fitness the day the goal was set: none then, all of it at the goal")
    func progress() {
        let goal = RunGoal(distance: .fiveK, minutes: 20)
        let now = RaceOutlook.evaluate(runs: runs, goal: goal).vdot!
        #expect(RaceOutlook.evaluate(runs: runs, goal: goal).goalProgress == nil)
        #expect(RaceOutlook.evaluate(runs: runs, goal: goal, goalStartVDOT: now).goalProgress == 0)
        let halfway = now - (goal.vdot - now)
        #expect(abs(RaceOutlook.evaluate(runs: runs, goal: goal, goalStartVDOT: halfway).goalProgress! - 0.5) < 0.001)
        #expect(RaceOutlook.evaluate(runs: runs, goal: RunGoal(distance: .fiveK, minutes: 26), goalStartVDOT: now).goalProgress == 1)
    }

    @Test("A flat trend, or too few weeks of runs, projects nothing")
    func noProjection() {
        let flat = improving(weeks: 14, from: 25, secondsFaster: 0)
        #expect(RaceOutlook.evaluate(runs: flat, goal: RunGoal(distance: .fiveK, minutes: 20)).projectedDate == nil)
        let short = improving(weeks: 3, from: 26, secondsFaster: 30)
        let outlook = RaceOutlook.evaluate(runs: short, goal: RunGoal(distance: .fiveK, minutes: 20))
        #expect(outlook.vdotPerWeek == nil)
        #expect(outlook.projectedDate == nil)
    }

    @Test("History is weekly, oldest first, and skips weeks with nothing to read")
    func history() {
        let history = RunPacing.fitnessHistory(from: runs, weeks: 26)
        #expect(!history.isEmpty)
        #expect(history.map(\.date) == history.map(\.date).sorted())
        // The long run is 16 days old and the 10 km 13: readings two, one and no weeks back have a run
        // in the eight weeks before them, and the earlier ones are left out.
        #expect(history.count == 3)
        #expect(history.first!.vdot < history.last!.vdot) // two weeks back only the easy long run counts
    }
}

@Suite("Quality runs")
struct QualityRunTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test("The rotation gives one of each workout every three weeks, and the same one all week")
    func rotation() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let weeks = (0..<6).map { QualityWorkout.rotation(weekStart: calendar.date(byAdding: .weekOfYear, value: $0, to: monday)!, calendar: calendar) }
        #expect(Set(weeks.prefix(3)) == Set(QualityWorkout.allCases))
        #expect(Array(weeks.prefix(3)) == Array(weeks.suffix(3)))
        let thursday = calendar.date(byAdding: .day, value: 3, to: monday)!
        #expect(QualityWorkout.rotation(weekStart: thursday, calendar: calendar) == weeks[0])
    }

    @Test("Speed reps are faster than intervals, intervals faster than threshold")
    func paceOrder() {
        let vdot = 38.4
        let speed = RunPacing.workPace(.speed, vdot: vdot)
        let intervals = RunPacing.workPace(.intervals, vdot: vdot)
        let threshold = RunPacing.workPace(.threshold, vdot: vdot)
        #expect(speed.slowest < intervals.slowest)
        #expect(intervals.slowest < threshold.fastest)
        #expect(speed.fastest < speed.slowest)
        // Daniels' tables for VDOT 38: I about 4:52 a km, R about 1:52 a 400 m (4:40 a km).
        #expect(abs((intervals.fastest + intervals.slowest) / 2 - 292) <= 8)
        #expect(abs((speed.fastest + speed.slowest) / 2 - 280) <= 8)
    }

    @Test("Forty minutes of threshold is ten easy, twenty at threshold, ten easy")
    func threshold() {
        let structure = QualityStructure.fitting(.threshold, plannedMinutes: 40, pace: nil)
        #expect(structure.warmUpMinutes == 10)
        #expect(structure.workMinutes == 20)
        #expect(structure.coolDownMinutes == 10)
        #expect(structure.repeats == 1)
    }

    @Test("Intervals and reps fill the planned minutes within their bounds", arguments: [30.0, 45, 60, 75])
    func fits(minutes: Double) {
        let intervals = QualityStructure.fitting(.intervals, plannedMinutes: minutes, pace: PaceRange(fastest: 285, slowest: 295))
        #expect((3...6).contains(intervals.repeats))
        #expect(intervals.repeatKm == 1)
        let speed = QualityStructure.fitting(.speed, plannedMinutes: minutes, pace: PaceRange(fastest: 275, slowest: 285))
        #expect((4...8).contains(speed.repeats))
        #expect(speed.repeatKm == 0.4)
        for structure in [intervals, speed] {
            #expect(structure.warmUpMinutes >= 10 && structure.coolDownMinutes >= 10)
            // Over the plan only when the fewest repeats do not fit; otherwise within a couple of minutes of it.
            if structure.repeats > (structure.workout == .intervals ? 3 : 4) {
                #expect(abs(structure.totalMinutes - minutes) < 2.5)
            }
        }
    }

    @Test("A quality target carries its workout, zone and structure")
    func target() {
        let target = RunPacing.target(for: .quality, vdot: 40, zones: HeartRateZones(maximum: 190, resting: 50), workout: .intervals, plannedMinutes: 50)
        #expect(target.workout == .intervals)
        #expect(target.zone == 5)
        #expect(target.structure?.workout == .intervals)
        #expect(target.easyPace != nil)
        let easy = RunPacing.target(for: .easy, vdot: 40, zones: nil)
        #expect(easy.workout == nil && easy.structure == nil)
    }
}
