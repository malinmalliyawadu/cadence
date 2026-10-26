import Foundation
import Testing
@testable import TrainingEngine

@Suite("Workout export import")
struct ImportTests {
    let fixture = """
    Date,Exercise,Reps,Weight(kg),Duration(s),Distance(m),Incline,Resistance,isWarmup,Note,multiplier
    2026-10-24 23:52:23 +0000,Hammerstrength Shoulder Press, 8,25.0,0.0,0.0,0.0,0.0,true,, 2.0
    2026-10-24 23:52:23 +0000,Hammerstrength Shoulder Press, 8,45.0,0.0,0.0,0.0,0.0,false,, 2.0
    2026-10-24 23:52:23 +0000,Hammerstrength Shoulder Press, 8,45.0,0.0,0.0,0.0,0.0,false,, 2.0
    2026-10-24 23:55:00 +0000,Cable Lateral Raise, 12,10.0,0.0,0.0,0.0,0.0,false,"note, with comma", 2.0
    2026-10-24 23:58:00 +0000,Some Unknown Machine, 10,30.0,0.0,0.0,0.0,0.0,false,, 1.0
    2026-10-24 23:59:00 +0000,Assisted Pull Up, 10,30.0,0.0,0.0,0.0,0.0,false,, 0.0
    2026-10-23 06:00:00 +0000,Running, 0,0.0,13408.27,32008.08,0.0,0.0,false,, 0.0
    2026-10-21 06:00:00 +0000,Running, 0,0.0,2652.73,5006.0,0.0,0.0,false,, 0.0
    2026-10-21 07:00:00 +0000,Running, 0,0.0,120.0,300.0,0.0,0.0,false,, 0.0
    2026-10-20 06:00:00 +0000,Walking, 0,0.0,1807.75,2241.0,0.0,0.0,false,, 0.0
    2026-10-19 20:00:00 +0000,Leg Press, 10,120.0,0.0,0.0,0.0,0.0,false,, 1.0
    2026-10-19 20:05:00 +0000,Seated Leg Curl, 12,40.0,0.0,0.0,0.0,0.0,false,, 1.0
    2026-10-19 20:10:00 +0000,Machine Hip Abductor, 15,50.0,0.0,0.0,0.0,0.0,false,, 1.0
    """

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return c
    }

    @Test("Strength rows group by local day with warm-ups kept but not counted")
    func strength() throws {
        let result = try WorkoutExportParser.parse(fixture, calendar: calendar)
        #expect(result.strength.count == 2)
        let upper = result.strength.last!
        #expect(upper.exercises.map(\.exerciseID) == ["hs-shoulder-press", "cable-lateral-raise"])
        #expect(upper.exercises[0].sets.count == 3)
        #expect(upper.exercises[0].workingSets.count == 2)
        #expect(upper.half == .upper)
        #expect(upper.focus == .shoulders)
        let lower = result.strength.first!
        #expect(lower.half == .lower)
        #expect(lower.workingSetCount == 3)
    }

    @Test("Runs are classified and same-day fragments merge")
    func runs() throws {
        let result = try WorkoutExportParser.parse(fixture, calendar: calendar)
        #expect(result.runs.count == 2)
        let long = result.runs.last!
        #expect(long.kind == .long)
        #expect(abs(long.kilometres - 32.0) < 0.1)
        let easy = result.runs.first!
        #expect(easy.kind == .easy)
        #expect(abs(easy.seconds - 2652.73) < 0.01, "a 2 minute fragment is dropped, not merged")
    }

    @Test("Unknown names are reported, ignored names and walks are skipped")
    func unmapped() throws {
        let result = try WorkoutExportParser.parse(fixture, calendar: calendar)
        #expect(result.unmapped == ["Some Unknown Machine": 1])
        #expect(result.skippedActivities == ["Walking": 1])
        #expect(!result.strength.flatMap(\.exercises).contains { $0.exerciseID == "pull-up" })
    }

    @Test("Quoted fields with commas parse")
    func quoting() {
        let rows = CSV.rows(from: "a,\"b, c\",\"say \"\"hi\"\"\"\r\n1,2,3\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["1", "2", "3"]])
    }

    @Test("Missing columns are an error")
    func missingColumns() {
        #expect(throws: WorkoutExportParser.ParseError.missingColumns(["iswarmup"])) {
            try WorkoutExportParser.parse("Date,Exercise,Reps,Weight(kg),Duration(s),Distance(m)\n")
        }
    }

    @Test("Every alias points at a catalogue movement")
    func aliasesResolve() {
        let names = ["Hammerstrength Incline Chest Press", "Cable Tricep Pushdown", "Machine Fly", "Smith Machine Calf Raise", "Palms-Up Barbell Wrist Curl", "Lying Hamstrings Curl", "hammer curls", "LEG EXTENSION"]
        for name in names {
            let id = ExerciseAliases.exerciseID(for: name)
            #expect(id != nil, "\(name) did not resolve")
            #expect(id.flatMap(ExerciseLibrary.exercise(id:)) != nil, "\(name) resolved to a missing id \(id ?? "")")
        }
    }

    @Test("The generator opens on the movement the athlete actually logs")
    func familiarity() {
        let history = (0..<6).map { week in
            ExerciseHistoryEntry(exerciseID: "hs-incline-press", date: .now.addingTimeInterval(-Double(week) * 7 * 86_400), targetReps: 8...10, targetRIR: 2, sets: [PerformedSet(weightKg: 40, reps: 8, rir: 2)])
        }
        let session = WorkoutGenerator.generate(StrengthSessionRequest(half: .upper, focus: .chest, history: history))
        #expect(session.prescriptions.first?.exercise.id == "hs-incline-press")
    }
}
