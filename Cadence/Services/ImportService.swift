import Foundation
import SwiftData
import TrainingEngine

#if DEBUG
/// Turns a parsed workout export into completed sessions in the store. Development only:
/// reached through the `-importCSV <path>` launch argument to seed a simulator with real history.
@MainActor
enum ImportService {
    struct Summary: Sendable, Equatable {
        var strengthSessions = 0
        var runs = 0
        var skippedExisting = 0
        var unmapped: [String: Int] = [:]
        var skippedActivities: [String: Int] = [:]

        var message: String {
            var lines = ["\(strengthSessions) strength sessions and \(runs) runs imported."]
            if skippedExisting > 0 { lines.append("\(skippedExisting) already in Cadence, left alone.") }
            if !unmapped.isEmpty {
                let names = unmapped.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) (\($0.value))" }
                lines.append("Not recognised: \(names.joined(separator: ", ")).")
            }
            if !skippedActivities.isEmpty {
                lines.append("Skipped \(skippedActivities.keys.sorted().joined(separator: ", ").lowercased()).")
            }
            return lines.joined(separator: " ")
        }
    }

    /// Reps in reserve is not in the export. Two is the working-set norm and keeps the first
    /// Cadence session from over- or under-shooting.
    static let assumedRIR = 2

    static func importExport(at url: URL, replacingExisting: Bool, in context: ModelContext, coordinator: PlanCoordinator) throws -> Summary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try WorkoutExportParser.parse(text, calendar: coordinator.calendar)
        return apply(parsed, replacingExisting: replacingExisting, in: context, coordinator: coordinator)
    }

    static func apply(_ parsed: WorkoutExportParser.Result, replacingExisting: Bool, in context: ModelContext, coordinator: PlanCoordinator) -> Summary {
        if replacingExisting { coordinator.deleteAllSessions(in: context) }
        let calendar = coordinator.calendar
        let existingKeys = Set(((try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []).compactMap(\.importKey))
        var summary = Summary(unmapped: parsed.unmapped, skippedActivities: parsed.skippedActivities)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var equipment = Set<Equipment>()
        var lastFocus: [BodyHalf: FocusArea] = [:]

        for imported in parsed.strength {
            let key = "csv:strength:\(dayFormatter.string(from: imported.date))"
            if existingKeys.contains(key) { summary.skippedExisting += 1; continue }
            let minutes = imported.estimatedMinutes.rounded()
            let session = TrainingSession(date: imported.date, modality: .strength, plannedMinutes: minutes, weekStart: coordinator.weekStart(containing: imported.date))
            session.importKey = key
            session.half = imported.half
            session.focus = imported.focus
            session.status = .completed
            session.completedAt = imported.date.addingTimeInterval(minutes * 60)
            session.actualMinutes = minutes
            for (order, exercise) in imported.exercises.enumerated() {
                let working = exercise.workingSets
                guard !working.isEmpty else { continue }
                let reps = working.map(\.reps)
                let planned = PlannedExercise(exerciseID: exercise.exerciseID, order: order, sets: working.count, repRange: (reps.min() ?? 8)...(reps.max() ?? 12), targetRIR: assumedRIR)
                planned.sets = working.enumerated().map { index, set in
                    let record = SetRecord(index: index, weightKg: set.weightKg, reps: set.reps, rir: assumedRIR)
                    record.completedAt = session.completedAt
                    return record
                }
                session.exercises.append(planned)
                if let catalogued = ExerciseLibrary.exercise(id: exercise.exerciseID) { equipment.insert(catalogued.equipment) }
            }
            session.rpe = TrainingLoad.strengthSessionRPE(meanRIR: Double(assumedRIR))
            if let focus = imported.focus { lastFocus[imported.half] = focus }
            context.insert(session)
            summary.strengthSessions += 1
        }

        for run in parsed.runs {
            let key = "csv:run:\(dayFormatter.string(from: run.date))"
            if existingKeys.contains(key) { summary.skippedExisting += 1; continue }
            let minutes = (run.minutes).rounded()
            let session = TrainingSession(date: run.date, modality: .running, plannedMinutes: minutes, weekStart: coordinator.weekStart(containing: run.date))
            session.importKey = key
            session.runKind = run.kind
            session.status = .completed
            session.completedAt = run.date.addingTimeInterval(run.seconds)
            session.actualMinutes = minutes
            session.distanceKm = (run.kilometres * 10).rounded() / 10
            session.rpe = run.kind.defaultRPE
            context.insert(session)
            summary.runs += 1
        }

        let profile = coordinator.profile(in: context)
        if !equipment.isEmpty {
            equipment.insert(.bodyweight)
            profile.equipment = equipment
        }
        if let upper = lastFocus[.upper] { profile.nextUpperFocus = upper.next }
        if let lower = lastFocus[.lower] { profile.nextLowerFocus = lower.next }
        try? context.save()
        return summary
    }
}
#endif
