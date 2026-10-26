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

    /// Adds the export's sessions to the store. A day that already holds the work keeps it (a
    /// lift with logged sets, a completed run, say from Health), so importing on top of real use
    /// never duplicates. Anything else of that modality on the day, planned, skipped or marked
    /// done without sets, gives way to what the export shows was done. `replacingExisting`
    /// wipes every session first, for reseeding a simulator after the parser changes.
    static func apply(_ parsed: WorkoutExportParser.Result, replacingExisting: Bool, in context: ModelContext, coordinator: PlanCoordinator) -> Summary {
        if replacingExisting { coordinator.deleteAllSessions(in: context) }
        let calendar = coordinator.calendar
        let existing = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
        let existingKeys = Set(existing.compactMap(\.importKey))
        var summary = Summary(unmapped: parsed.unmapped, skippedActivities: parsed.skippedActivities)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.dateFormat = "yyyy-MM-dd"

        /// True when the day already holds the work; otherwise clears the way for the import.
        func alreadyLogged(_ modality: Modality, on date: Date) -> Bool {
            let sameDay = existing.filter { !$0.isDeleted && $0.modality == modality && calendar.isDate($0.date, inSameDayAs: date) }
            if sameDay.contains(where: { $0.status == .completed && (modality != .strength || $0.loggedSetCount > 0) }) { return true }
            sameDay.forEach(context.delete)
            return false
        }

        var equipment = Set<Equipment>()
        var lastImported: [BodyHalf: (date: Date, focus: FocusArea)] = [:]

        for imported in parsed.strength {
            let key = "csv:strength:\(dayFormatter.string(from: imported.date))"
            if existingKeys.contains(key) || alreadyLogged(.strength, on: imported.date) { summary.skippedExisting += 1; continue }
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
                    // Unrated: progression assumes the last set landed on the target RIR.
                    let record = SetRecord(index: index, weightKg: set.weightKg, reps: set.reps)
                    record.completedAt = session.completedAt
                    return record
                }
                session.exercises.append(planned)
                if let catalogued = ExerciseLibrary.exercise(id: exercise.exerciseID) { equipment.insert(catalogued.equipment) }
            }
            session.rpe = TrainingLoad.strengthSessionRPE(meanRIR: Double(assumedRIR))
            if let focus = imported.focus, imported.date >= lastImported[imported.half]?.date ?? .distantPast {
                lastImported[imported.half] = (imported.date, focus)
            }
            context.insert(session)
            summary.strengthSessions += 1
        }

        for run in parsed.runs {
            let key = "csv:run:\(dayFormatter.string(from: run.date))"
            if existingKeys.contains(key) || alreadyLogged(.running, on: run.date) { summary.skippedExisting += 1; continue }
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
            profile.equipment = replacingExisting ? equipment : profile.equipment.union(equipment)
        }
        // Advance the focus rotation only where the import holds the latest session of that half.
        for (half, last) in lastImported {
            let later = existing.contains { !$0.isDeleted && $0.modality == .strength && $0.status == .completed && $0.half == half && $0.date > last.date }
            guard !later else { continue }
            switch half {
            case .upper: profile.nextUpperFocus = last.focus.next
            case .lower: profile.nextLowerFocus = last.focus.next
            }
        }
        try? context.save()
        return summary
    }
}
#endif
