import Foundation

/// Parses a workout-log CSV export (columns: Date, Exercise, Reps, Weight(kg), Duration(s),
/// Distance(m), Incline, Resistance, isWarmup, Note, multiplier) into sessions the app can
/// store. Strength rows group by local day; duration rows become runs or are skipped.
public enum WorkoutExportParser {
    public struct ImportedSet: Sendable, Hashable {
        public let weightKg: Double
        public let reps: Int
        public let isWarmup: Bool
    }

    public struct ImportedExercise: Sendable, Hashable {
        public let exerciseID: String
        public let sets: [ImportedSet]
        public var workingSets: [ImportedSet] { sets.filter { !$0.isWarmup && $0.reps > 0 } }
    }

    public struct ImportedStrengthSession: Sendable, Hashable, Identifiable {
        public var id: Date { date }
        public let date: Date
        public let exercises: [ImportedExercise]

        public var muscles: [MuscleGroup] {
            exercises.compactMap { ExerciseLibrary.exercise(id: $0.exerciseID)?.primary }
        }

        /// Upper or lower by majority of primary muscles. Mixed days go to whichever has more.
        public var half: BodyHalf {
            let upper = muscles.filter { $0.half == .upper }.count
            return upper * 2 >= muscles.count ? .upper : .lower
        }

        /// The focus area with the most working sets, if any muscle fits a focus.
        public var focus: FocusArea? {
            var counts: [FocusArea: Int] = [:]
            for exercise in exercises {
                guard let muscle = ExerciseLibrary.exercise(id: exercise.exerciseID)?.primary else { continue }
                for area in FocusArea.areas(for: half) where area.muscles.contains(muscle) {
                    counts[area, default: 0] += exercise.workingSets.count
                }
            }
            return counts.max { $0.value < $1.value }?.key
        }

        public var workingSetCount: Int { exercises.map { $0.workingSets.count }.reduce(0, +) }

        /// About two and a half minutes per working set plus a warm-up.
        public var estimatedMinutes: Double { 8 + Double(workingSetCount) * 2.5 }
    }

    public struct ImportedRun: Sendable, Hashable, Identifiable {
        public var id: Date { date }
        public let date: Date
        public let seconds: Double
        public let meters: Double

        public var minutes: Double { seconds / 60 }
        public var kilometres: Double { meters / 1000 }
        /// Anything from about 14 km up is a long run for this athlete's volume.
        public var kind: RunKind { kilometres >= 14 ? .long : .easy }
    }

    public struct Result: Sendable {
        public var strength: [ImportedStrengthSession] = []
        public var runs: [ImportedRun] = []
        /// Exercise names that matched nothing in the catalogue, with their working set counts.
        public var unmapped: [String: Int] = [:]
        /// Duration-based activities that were skipped (walking, hiking, stair stepper).
        public var skippedActivities: [String: Int] = [:]
    }

    public enum ParseError: Error, Equatable {
        case missingHeader
        case missingColumns([String])
    }

    public static func parse(_ text: String, calendar: Calendar = .current) throws -> Result {
        var lines = CSV.rows(from: text)
        guard let header = lines.first else { throw ParseError.missingHeader }
        lines.removeFirst()
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) })
        let required = ["date", "exercise", "reps", "weight(kg)", "duration(s)", "distance(m)", "iswarmup"]
        let missing = required.filter { columns[$0] == nil }
        guard missing.isEmpty else { throw ParseError.missingColumns(missing) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var result = Result()
        // Day -> ordered exercise IDs -> sets, preserving the order exercises first appeared.
        var strengthByDay: [Date: (order: [String], sets: [String: [ImportedSet]], first: Date)] = [:]
        var runRows: [ImportedRun] = []

        for row in lines where row.count >= header.count {
            func field(_ name: String) -> String { row[columns[name]!].trimmingCharacters(in: .whitespaces) }
            guard let date = formatter.date(from: field("date")) else { continue }
            let name = field("exercise")
            let seconds = Double(field("duration(s)")) ?? 0
            let meters = Double(field("distance(m)")) ?? 0

            if seconds > 0 {
                let normalized = ExerciseAliases.normalize(name)
                if normalized == "running", seconds >= 300 {
                    runRows.append(ImportedRun(date: date, seconds: seconds, meters: meters))
                } else if normalized != "running" {
                    result.skippedActivities[name, default: 0] += 1
                }
                continue
            }

            let reps = Int(Double(field("reps")) ?? 0)
            let weight = Double(field("weight(kg)")) ?? 0
            let isWarmup = field("iswarmup").lowercased() == "true"
            guard reps > 0 else { continue }

            if ExerciseAliases.ignoredNames.contains(ExerciseAliases.normalize(name)) { continue }
            guard let exerciseID = ExerciseAliases.exerciseID(for: name) else {
                if !isWarmup { result.unmapped[name, default: 0] += 1 }
                continue
            }

            let day = calendar.startOfDay(for: date)
            var bucket = strengthByDay[day] ?? (order: [], sets: [:], first: date)
            if bucket.sets[exerciseID] == nil { bucket.order.append(exerciseID) }
            bucket.sets[exerciseID, default: []].append(ImportedSet(weightKg: weight, reps: reps, isWarmup: isWarmup))
            bucket.first = min(bucket.first, date)
            strengthByDay[day] = bucket
        }

        result.strength = strengthByDay.values.map { bucket in
            ImportedStrengthSession(date: bucket.first, exercises: bucket.order.map { ImportedExercise(exerciseID: $0, sets: bucket.sets[$0] ?? []) })
        }
        .filter { $0.workingSetCount > 0 }
        .sorted { $0.date < $1.date }

        // Several short "Running" rows on one day (a watch split, a false start) collapse into one run.
        var runsByDay: [Date: ImportedRun] = [:]
        for run in runRows {
            let day = calendar.startOfDay(for: run.date)
            if let existing = runsByDay[day] {
                runsByDay[day] = ImportedRun(date: min(existing.date, run.date), seconds: existing.seconds + run.seconds, meters: existing.meters + run.meters)
            } else {
                runsByDay[day] = run
            }
        }
        result.runs = runsByDay.values.sorted { $0.date < $1.date }
        return result
    }
}

/// Minimal RFC 4180 reader: quoted fields, doubled quotes, CRLF or LF line endings.
/// Works on Unicode scalars because Swift folds "\r\n" into one Character, which would
/// otherwise hide the line break from a per-character scan.
enum CSV {
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }

        while let char = next() {
            if inQuotes {
                if char == "\"" {
                    if let peek = next() {
                        if peek == "\"" { field.append("\"") } else { inQuotes = false; pending = peek }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",": endField()
                case "\r": break
                case "\n":
                    endField()
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(char)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endField()
            rows.append(row)
        }
        return rows
    }
}
