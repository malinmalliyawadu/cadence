import Foundation
import Testing
@testable import TrainingEngine

@Suite("Week planner")
struct WeekPlannerTests {
    let calendar = Calendar(identifier: .gregorian)
    // A Monday.
    let monday = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 26))!

    func day(_ index: Int) -> Date { calendar.date(byAdding: .day, value: index, to: monday)! }

    func forecast(_ index: Int, temp: Double = 14, rain: Double = 0.1, wind: Double = 10) -> DayForecast {
        DayForecast(date: day(index), tempMaxC: temp, tempMinC: temp - 6, precipitationProbability: rain, precipitationMm: rain * 10, windKph: wind, uvIndex: 5, weatherCode: rain > 0.5 ? 61 : 1)
    }

    var strength: [StrengthSlot] {
        [
            StrengthSlot(WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .chest))),
            StrengthSlot(WorkoutGenerator.generate(StrengthSessionRequest(half: .lower, focus: .quads))),
            StrengthSlot(WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .back))),
            StrengthSlot(WorkoutGenerator.generate(StrengthSessionRequest(half: .lower, focus: .posteriorChain))),
        ]
    }

    func emptyLoad() -> LoadSnapshot { LoadAnalysis.snapshot(entries: [], asOf: monday, calendar: calendar) }

    func plan(prefs: PlannerPreferences, forecasts: [DayForecast]? = nil, load: LoadSnapshot? = nil) -> WeekPlan {
        WeekPlanner.plan(.init(preferences: prefs, strength: strength, forecasts: forecasts ?? (0..<7).map { forecast($0) }, load: load ?? emptyLoad(), calendar: calendar))
    }

    func strengthDays(_ plan: WeekPlan) -> [(Int, BodyHalf)] {
        plan.days.flatMap { day in day.sessions.compactMap { session -> (Int, BodyHalf)? in
            if case .strength(_, let half, _) = session.kind { return (day.dayIndex, half) }
            return nil
        } }
    }

    func runDays(_ plan: WeekPlan) -> [(Int, RunKind)] {
        plan.days.flatMap { day in day.sessions.compactMap { session -> (Int, RunKind)? in
            if case .run(let kind) = session.kind { return (day.dayIndex, kind) }
            return nil
        } }
    }

    @Test("Default week places everything, alternates upper and lower, and leaves a rest day")
    func defaultWeek() {
        let plan = plan(prefs: PlannerPreferences(weekStart: monday))
        #expect(plan.sessions.count == 7)
        let halves = strengthDays(plan).map(\.1)
        #expect(halves == [.upper, .lower, .upper, .lower])
        #expect(plan.days.contains { $0.isRest })
        #expect(plan.days.allSatisfy { $0.sessions.filter(\.isHard).count <= 1 })
    }

    @Test("Unavailable days are never used")
    func unavailable() {
        let plan = plan(prefs: PlannerPreferences(weekStart: monday, unavailableDays: [2, 6]))
        #expect(plan.days[2].isRest)
        #expect(plan.days[6].isRest)
        #expect(plan.sessions.count == 7)
    }

    @Test("The long run goes to the best-weather weekend day")
    func weatherDrivesLongRun() {
        var forecasts = (0..<7).map { forecast($0, temp: 12, rain: 0.8) } // wet week
        forecasts[6] = forecast(6, temp: 14, rain: 0.05)                      // except Sunday
        let plan = plan(prefs: PlannerPreferences(weekStart: monday, preferredLongRunDay: nil), forecasts: forecasts)
        let long = runDays(plan).first { $0.1 == .long }
        #expect(long?.0 == 6)
    }

    @Test("Lower-body days are kept away from the long run")
    func spacing() {
        let plan = plan(prefs: PlannerPreferences(weekStart: monday))
        let lowers = strengthDays(plan).filter { $0.1 == .lower }.map(\.0)
        let long = runDays(plan).first { $0.1 == .long }!.0
        #expect(lowers.allSatisfy { abs($0 - long) >= 2 }, "lowers \(lowers), long \(long)")
    }

    @Test("A spiked week is planned below last week's load and brings the ratio back down")
    func loadBudget() {
        var entries = (7..<84).map { LoadEntry(date: calendar.date(byAdding: .day, value: -$0, to: monday)!, modality: .running, load: 350) }
        entries += (1...7).map { LoadEntry(date: calendar.date(byAdding: .day, value: -$0, to: monday)!, modality: .running, load: 900) }
        let snapshot = LoadAnalysis.snapshot(entries: entries, planningOn: monday, calendar: calendar)
        #expect(snapshot.zone == .elevated || snapshot.zone == .danger, "acwr \(snapshot.acwr ?? 0)")

        let spikedPlan = plan(prefs: PlannerPreferences(weekStart: monday), load: snapshot)
        let lastWeek = snapshot.weekLoad
        #expect(spikedPlan.targetLoad < lastWeek * 0.8, "target \(spikedPlan.targetLoad) vs last week \(lastWeek)")
        #expect(spikedPlan.readiness.loadMultiplier < 1)

        // Simulate following the plan: the ratio should be back in the sweet spot by next Sunday.
        let daily = spikedPlan.targetLoad / 7
        let nextWeek = entries + (0..<7).map { LoadEntry(date: calendar.date(byAdding: .day, value: $0, to: monday)!, modality: .running, load: daily) }
        let after = LoadAnalysis.snapshot(entries: nextWeek, asOf: calendar.date(byAdding: .day, value: 6, to: monday)!, calendar: calendar)
        #expect(after.acwr! < 1.3 && after.acwr! > 0.8, "acwr after a week on plan \(after.acwr!)")
    }

    @Test("Steady training earns a small weekly progression")
    func steadyProgression() {
        let entries = (0..<84).map { LoadEntry(date: calendar.date(byAdding: .day, value: -$0, to: monday)!, modality: .running, load: 350) }
        let snapshot = LoadAnalysis.snapshot(entries: entries, asOf: monday, calendar: calendar)
        let weekPlan = plan(prefs: PlannerPreferences(weekStart: monday), load: snapshot)
        #expect(weekPlan.targetLoad > 350 * 7 && weekPlan.targetLoad < 350 * 7 * 1.12)
    }

    @Test("Run durations are multiples of five within sane bounds")
    func runBounds() {
        let plan = plan(prefs: PlannerPreferences(weekStart: monday, easyRuns: 2, includeQualityRun: true))
        for session in plan.sessions {
            guard case .run(let kind) = session.kind else { continue }
            #expect(session.plannedMinutes.truncatingRemainder(dividingBy: 5) == 0)
            switch kind {
            case .easy: #expect((25...60).contains(session.plannedMinutes))
            case .long: #expect((45...120).contains(session.plannedMinutes))
            case .quality: #expect((30...55).contains(session.plannedMinutes))
            }
        }
    }

    @Test("Without two-a-days nothing shares a day")
    func noDoubles() {
        let plan = plan(prefs: PlannerPreferences(weekStart: monday, easyRuns: 1, yogaSessions: 1, allowTwoADays: false))
        #expect(plan.days.allSatisfy { $0.sessions.count <= 1 })
        #expect(plan.sessions.count == 7)
    }

    @Test("A busy week still produces a complete plan quickly")
    func heavyWeek() {
        let clock = ContinuousClock()
        let start = clock.now
        let plan = plan(prefs: PlannerPreferences(weekStart: monday, easyRuns: 2, includeQualityRun: true, yogaSessions: 2))
        let elapsed = clock.now - start
        #expect(plan.sessions.count == 10)
        #expect(elapsed < .seconds(2), "took \(elapsed)")
    }

    @Test("Running score prefers mild dry still days", arguments: [
        (14.0, 0.1, 10.0, true),
        (28.0, 0.1, 10.0, false),
        (14.0, 0.9, 10.0, false),
        (14.0, 0.1, 50.0, false),
    ])
    func runningScore(temp: Double, rain: Double, wind: Double, good: Bool) {
        let f = DayForecast(date: monday, tempMaxC: temp, tempMinC: temp - 5, precipitationProbability: rain, precipitationMm: rain * 8, windKph: wind, uvIndex: 4, weatherCode: 1)
        #expect(f.isGoodRunningDay == good, "score \(f.runningScore)")
    }
}
