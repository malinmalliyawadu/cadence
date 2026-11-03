import Foundation
import Testing
@testable import TrainingEngine

@Suite("Training load")
struct LoadAnalysisTests {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSince1970: 1_790_000_000)

    func days(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today)! }

    @Test("No history means building, not zero")
    func building() {
        let snapshot = LoadAnalysis.snapshot(entries: [], asOf: today, calendar: calendar)
        #expect(snapshot.acwr == nil)
        #expect(snapshot.zone == .building)
        #expect(Readiness.from(snapshot).loadMultiplier == 1)
    }

    @Test("Steady training settles at a ratio of one")
    func steady() {
        let entries = (0..<84).map { LoadEntry(date: days($0), modality: .strength, load: 300) }
        let snapshot = LoadAnalysis.snapshot(entries: entries, asOf: today, calendar: calendar)
        #expect(abs(snapshot.acwr! - 1) < 0.05, "acwr was \(snapshot.acwr!)")
        #expect(snapshot.zone == .optimal)
        #expect(snapshot.weekLoad == 2100)
    }

    @Test("A sudden jump in load lands in the elevated or danger zone")
    func spike() {
        var entries = (7..<84).map { LoadEntry(date: days($0), modality: .running, load: 200) }
        entries += (0..<7).map { LoadEntry(date: days($0), modality: .running, load: 500) }
        let snapshot = LoadAnalysis.snapshot(entries: entries, asOf: today, calendar: calendar)
        #expect(snapshot.acwr! > 1.3, "acwr was \(snapshot.acwr!)")
        let readiness = Readiness.from(snapshot)
        #expect(readiness.loadMultiplier < 1)
        #expect(readiness.setReduction == 1)
    }

    @Test("A week off drops the ratio below 0.8")
    func taper() {
        let entries = (10..<84).map { LoadEntry(date: days($0), modality: .strength, load: 300) }
        let snapshot = LoadAnalysis.snapshot(entries: entries, asOf: today, calendar: calendar)
        #expect(snapshot.acwr! < 0.8)
        #expect(snapshot.zone == .undertrained)
    }

    @Test("Monotony punishes identical days and rewards variety")
    func monotony() {
        let flat = (0..<84).map { LoadEntry(date: days($0), modality: .strength, load: 300) }
        let flatSnapshot = LoadAnalysis.snapshot(entries: flat, asOf: today, calendar: calendar)
        #expect(flatSnapshot.monotony == nil, "zero standard deviation has no defined monotony")

        let varied = (0..<84).map { LoadEntry(date: days($0), modality: .strength, load: $0 % 2 == 0 ? 500 : 100) }
        let variedSnapshot = LoadAnalysis.snapshot(entries: varied, asOf: today, calendar: calendar)
        #expect(variedSnapshot.monotony! < 2)
        #expect(variedSnapshot.strain != nil)
    }

    @Test("Every week in the series is read as Foster reads the last")
    func weekly() {
        let varied = (0..<84).map { LoadEntry(date: days($0), modality: .strength, load: $0 % 3 == 0 ? 600 : 150) }
        let snapshot = LoadAnalysis.snapshot(entries: varied, asOf: today, calendar: calendar)
        let weeks = snapshot.weekly
        #expect(weeks.count == snapshot.series.count - 6)
        #expect(weeks.last?.date == snapshot.today?.date)
        #expect(weeks.last?.monotony == snapshot.monotony)
        #expect(weeks.last?.strain == snapshot.strain)
        #expect(weeks.last?.load == snapshot.weekLoad)

        let week = WeeklyLoad(date: today, days: [100, 100, 100, 300, 300, 300, 0])
        #expect(abs(week.mean - 1200.0 / 7) < 1e-9)
        #expect(abs(week.monotony! - week.mean / week.spread) < 1e-9)
        #expect(abs(week.strain! - 1200 * week.monotony!) < 1e-9)
        #expect(WeeklyLoad(date: today, days: Array(repeating: 0, count: 7)).monotony == nil)
    }

    @Test("A zone's effect can be read without a snapshot")
    func zoneEffects() {
        #expect(Readiness.from(zone: .optimal).weeklyLoadFactor == 1.08)
        #expect(Readiness.from(zone: .danger).loadMultiplier == 0.9)
        #expect(Readiness.from(zone: .elevated).setReduction == 1)
    }

    @Test("Loads on the same day aggregate")
    func sameDay() {
        let entries = [LoadEntry(date: today, modality: .strength, load: 300), LoadEntry(date: today.addingTimeInterval(3600), modality: .yoga, load: 250)]
        let snapshot = LoadAnalysis.snapshot(entries: entries, asOf: today, calendar: calendar)
        #expect(snapshot.today?.load == 550)
    }

    @Test("Strength session RPE falls as RIR rises")
    func strengthRPE() {
        #expect(TrainingLoad.strengthSessionRPE(meanRIR: 0) == 8.5)
        #expect(TrainingLoad.strengthSessionRPE(meanRIR: 2) == 6.5)
        #expect(TrainingLoad.strengthSessionRPE(meanRIR: 9) == 3)
    }
}
