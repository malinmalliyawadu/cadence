import Foundation
import SwiftData
import TrainingEngine

/// Every completed lift read per movement: each movement's trend points beside the sessions
/// they came from, and how many bests each session set. Plain values, so it can be worked out
/// away from the screen (`HistoryReader`) and handed over whole.
struct MovementHistory: Sendable {
    struct Movement: Identifiable, Sendable {
        let exercise: Exercise
        /// Oldest first, one per session the movement was logged in.
        let points: [ExerciseTrendPoint]
        /// What progression reads, in the same order.
        let entries: [ExerciseHistoryEntry]
        /// The session each point came from, in the same order.
        let sessionIDs: [UUID]

        var id: String { exercise.id }
    }

    /// What the history is worked out from, so a view works it out again only when these change.
    /// A finished session is not edited in place: reopening it takes it out of the finished ones.
    struct Inputs: Equatable {
        let sessions: [UUID]
        let bodyweightKg: Double
    }

    let movements: [Movement]
    /// Movements whose estimated max a session took past every earlier session's, by session.
    let bests: [UUID: Int]

    init(logged: [(entry: ExerciseHistoryEntry, sessionID: UUID)], bodyweightKg: Double) {
        var bests: [UUID: Int] = [:]
        var movements: [Movement] = []
        for (id, items) in Dictionary(grouping: logged, by: { $0.entry.exerciseID }) {
            guard let exercise = ExerciseLibrary.exercise(id: id) else { continue }
            // Sorted here so the points, which the engine sorts the same way, line up with their sessions.
            let ordered = items.sorted { $0.entry.date < $1.entry.date }
            let points = ExerciseTrend.points(for: exercise, history: ordered.map(\.entry), bodyweightKg: bodyweightKg)
            for (point, item) in zip(points, ordered) where point.isBest { bests[item.sessionID, default: 0] += 1 }
            movements.append(Movement(exercise: exercise, points: points, entries: ordered.map(\.entry), sessionIDs: ordered.map(\.sessionID)))
        }
        // The most recent first; movements from the same session alphabetically, so the order holds still.
        self.movements = movements.sorted { lhs, rhs in
            let l = lhs.points.last?.date ?? .distantPast, r = rhs.points.last?.date ?? .distantPast
            return l != r ? l > r : lhs.exercise.name < rhs.exercise.name
        }
        self.bests = bests
    }
}

/// Reads the finished lifts on a context of its own. A long history is thousands of logged sets,
/// and reading them on the main context held up taps for half a second.
@ModelActor
actor HistoryReader {
    /// Every finished movement, or only `exerciseID`'s.
    func history(bodyweightKg: Double, exerciseID: String? = nil) -> MovementHistory {
        let completed = SessionStatus.completed.rawValue
        let predicate: Predicate<PlannedExercise>
        if let exerciseID {
            predicate = #Predicate { $0.exerciseID == exerciseID && $0.session?.statusRaw == completed }
        } else {
            predicate = #Predicate { $0.session?.statusRaw == completed }
        }
        let exercises = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        let logged = exercises.compactMap { exercise in
            exercise.historyEntry.flatMap { entry in exercise.session.map { (entry: entry, sessionID: $0.id) } }
        }
        return MovementHistory(logged: logged, bodyweightKg: bodyweightKg)
    }

    /// Saves what the main context holds first, so a session finished a moment ago is in it. The
    /// reader is made off the main actor, or its context would run there.
    @MainActor static func history(in context: ModelContext, bodyweightKg: Double, exerciseID: String? = nil) async -> MovementHistory {
        try? context.save()
        let container = context.container
        return await Task.detached {
            await HistoryReader(modelContainer: container).history(bodyweightKg: bodyweightKg, exerciseID: exerciseID)
        }.value
    }
}
