import Foundation
import Testing
@testable import TrainingEngine

/// Runs the parser over a real export when CADENCE_EXPORT points at one. Skipped otherwise,
/// so CI never depends on a personal file. Prints coverage so alias gaps are easy to spot:
///   CADENCE_EXPORT=~/Downloads/WorkoutExport.csv swift test --filter RealExport
@Suite("Real export smoke test", .enabled(if: ProcessInfo.processInfo.environment["CADENCE_EXPORT"] != nil))
struct RealExportSmokeTest {
    @Test("Parses the export with high alias coverage")
    func coverage() throws {
        let path = NSString(string: ProcessInfo.processInfo.environment["CADENCE_EXPORT"]!).expandingTildeInPath
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let result = try WorkoutExportParser.parse(text)
        let mapped = result.strength.map(\.workingSetCount).reduce(0, +)
        let unmapped = result.unmapped.values.reduce(0, +)
        print("strength sessions \(result.strength.count), runs \(result.runs.count), working sets mapped \(mapped), unmapped \(unmapped)")
        print("unmapped names:", result.unmapped.sorted { $0.value > $1.value })
        print("skipped activities:", result.skippedActivities)
        let halves = result.strength.map(\.half)
        print("upper \(halves.filter { $0 == .upper }.count), lower \(halves.filter { $0 == .lower }.count)")
        print("focus spread:", Dictionary(grouping: result.strength.compactMap(\.focus), by: { $0 }).mapValues(\.count))
        print("long runs:", result.runs.filter { $0.kind == .long }.count, "easy:", result.runs.filter { $0.kind == .easy }.count)
        #expect(Double(unmapped) / Double(mapped + unmapped) < 0.02, "more than 2% of working sets did not map")
        #expect(!result.strength.isEmpty)
    }

    @Test("Warm-up rule matches which movements the athlete warmed up for")
    func warmUps() throws {
        let path = NSString(string: ProcessInfo.processInfo.environment["CADENCE_EXPORT"]!).expandingTildeInPath
        let result = try WorkoutExportParser.parse(String(contentsOfFile: path, encoding: .utf8))
        let exposures = result.strength.flatMap(\.exercises).filter { !$0.workingSets.isEmpty }
        var mismatches: [String: Int] = [:]
        for exposure in exposures {
            guard let exercise = ExerciseLibrary.exercise(id: exposure.exerciseID) else { continue }
            if WarmUp.needsWarmUp(exercise) != exposure.sets.contains(where: \.isWarmup) { mismatches[exercise.id, default: 0] += 1 }
        }
        let agreement = 1 - Double(mismatches.values.reduce(0, +)) / Double(exposures.count)
        print("warm-up agreement \(String(format: "%.1f", agreement * 100))% over \(exposures.count) exposures, mismatches:", mismatches.sorted { $0.value > $1.value })
        #expect(agreement > 0.9)
    }
}
