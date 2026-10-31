import Foundation
import SwiftData
import TrainingEngine

enum SessionStatus: String, Codable, Sendable {
    case planned, completed, skipped
}

/// One planned or completed session of any modality.
@Model
final class TrainingSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var modalityRaw: String
    var statusRaw: String
    var plannedMinutes: Double
    var actualMinutes: Double?
    /// Session RPE 0 ... 10, set by the athlete for runs and yoga, derived from RIR for strength.
    var rpe: Double?
    var notes: String
    var completedAt: Date?
    /// Start of the week this session was planned in. Lets a re-plan replace only this week's untouched sessions.
    var weekStart: Date
    /// Stable key for sessions created by an import, so importing the same file twice is a no-op.
    var importKey: String?
    /// The HealthKit workout this session was completed from, if any.
    var healthWorkoutID: String?
    /// Average heart rate over the workout, from Apple Health.
    var averageHeartRate: Double?
    /// Active energy over the workout, from Apple Health.
    var activeKilocalories: Double?

    // Strength
    var halfRaw: String?
    var focusRaw: String?
    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.session) var exercises: [PlannedExercise]
    /// The recovery multiplier today's loads are prescribed at, so a new reading re-prescribes only when it changes them.
    var recoveryFactor: Double = 1
    /// Recorded live by the watch, which saves the workout to Health, so finishing waits for that rather than saving an estimate.
    var recordedLive: Bool = false

    // Running
    var runKindRaw: String?
    var distanceKm: Double?

    /// Seconds per kilometre for a finished run.
    var actualPace: Double? {
        guard let distanceKm, distanceKm > 0, let minutes = actualMinutes else { return nil }
        return minutes * 60 / distanceKm
    }

    var runEffort: RunEffort? {
        guard modality == .running, status == .completed, let distanceKm, let minutes = actualMinutes else { return nil }
        return RunEffort(date: completedAt ?? date, distanceKm: distanceKm, minutes: minutes)
    }

    init(date: Date, modality: Modality, plannedMinutes: Double, weekStart: Date) {
        id = UUID()
        self.date = date
        modalityRaw = modality.rawValue
        statusRaw = SessionStatus.planned.rawValue
        self.plannedMinutes = plannedMinutes
        notes = ""
        self.weekStart = weekStart
        exercises = []
    }

    var modality: Modality { Modality(rawValue: modalityRaw) ?? .strength }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var half: BodyHalf? {
        get { halfRaw.flatMap(BodyHalf.init(rawValue:)) }
        set { halfRaw = newValue?.rawValue }
    }

    var focus: FocusArea? {
        get { focusRaw.flatMap(FocusArea.init(rawValue:)) }
        set { focusRaw = newValue?.rawValue }
    }

    var runKind: RunKind? {
        get { runKindRaw.flatMap(RunKind.init(rawValue:)) }
        set { runKindRaw = newValue?.rawValue }
    }

    var orderedExercises: [PlannedExercise] { exercises.sorted { $0.order < $1.order } }

    var title: String {
        switch modality {
        case .strength:
            if let half { return "\(half.displayName) body" }
            return "Strength"
        case .running:
            return runKind?.displayName ?? "Run"
        case .yoga:
            return "Hot yoga"
        }
    }

    var subtitle: String {
        switch modality {
        case .strength:
            if let focus { return "\(focus.displayName) focus" }
            return exercises.isEmpty ? "From Apple Health" : "Full session"
        case .running:
            if let distanceKm, status == .completed { return String(format: "%.1f km", distanceKm) }
            return "\(Int(plannedMinutes)) min"
        case .yoga:
            return "\(Int(plannedMinutes)) min"
        }
    }

    /// Mean RIR across the rated sets (each movement's final set), for strength sessions.
    var loggedMeanRIR: Double? {
        let rirs = exercises.flatMap(\.sets).filter { $0.completedAt != nil && $0.reps > 0 }.compactMap(\.rir)
        guard !rirs.isEmpty else { return nil }
        return Double(rirs.reduce(0, +)) / Double(rirs.count)
    }

    var loggedSetCount: Int { exercises.flatMap(\.sets).filter { $0.completedAt != nil }.count }
    var plannedSetCount: Int { exercises.map(\.targetSets).reduce(0, +) }

    /// Session-RPE load in arbitrary units. Planned sessions use their estimate; completed ones use what was logged.
    var load: Double {
        let minutes = actualMinutes ?? plannedMinutes
        switch modality {
        case .strength:
            let rir = loggedMeanRIR ?? meanTargetRIR
            return TrainingLoad.sessionLoad(rpe: rpe ?? TrainingLoad.strengthSessionRPE(meanRIR: rir), minutes: minutes)
        case .running:
            return TrainingLoad.sessionLoad(rpe: rpe ?? runKind?.defaultRPE ?? 5, minutes: minutes)
        case .yoga:
            return TrainingLoad.sessionLoad(rpe: rpe ?? 5, minutes: minutes)
        }
    }

    var meanTargetRIR: Double {
        guard !exercises.isEmpty else { return 2 }
        return Double(exercises.map(\.targetRIR).reduce(0, +)) / Double(exercises.count)
    }

    var loadEntry: LoadEntry? {
        guard status == .completed else { return nil }
        return LoadEntry(date: completedAt ?? date, modality: modality, load: load)
    }
}

@Model
final class PlannedExercise {
    var exerciseID: String
    var order: Int
    var targetSets: Int
    var repLower: Int
    var repUpper: Int
    var targetRIR: Int
    var prescribedWeightKg: Double?
    var isFocus: Bool
    var rationale: String
    var session: TrainingSession?
    @Relationship(deleteRule: .cascade, inverse: \SetRecord.exercise) var sets: [SetRecord]
    /// Warm-up sets ticked off, from the lightest. Warm-ups are never logged as sets.
    var warmUpsDone: Int = 0

    init(prescription: ExercisePrescription, order: Int) {
        exerciseID = prescription.exercise.id
        self.order = order
        targetSets = prescription.sets
        repLower = prescription.repRange.lowerBound
        repUpper = prescription.repRange.upperBound
        targetRIR = prescription.targetRIR
        prescribedWeightKg = prescription.weightKg
        isFocus = prescription.isFocus
        rationale = prescription.rationale
        sets = []
    }

    /// For imported history, where there was no prescription.
    init(exerciseID: String, order: Int, sets: Int, repRange: ClosedRange<Int>, targetRIR: Int) {
        self.exerciseID = exerciseID
        self.order = order
        targetSets = sets
        repLower = repRange.lowerBound
        repUpper = repRange.upperBound
        self.targetRIR = targetRIR
        prescribedWeightKg = nil
        isFocus = false
        rationale = "Imported from your previous log. Reps in reserve were not recorded, so 2 is assumed."
        self.sets = []
    }

    var exercise: Exercise? { ExerciseLibrary.exercise(id: exerciseID) }
    var name: String { exercise?.name ?? exerciseID }
    var repRange: ClosedRange<Int> { repLower...repUpper }
    var orderedSets: [SetRecord] { sets.sorted { $0.index < $1.index } }
    var completedSets: [SetRecord] { orderedSets.filter { $0.completedAt != nil } }
    var isComplete: Bool { completedSets.count >= targetSets }

    /// The record at a set position, logged or planned. Planned sets exist only once the athlete
    /// has changed their weight or reps; until then a set follows `target(at:)`.
    func record(at index: Int) -> SetRecord? { sets.first { $0.index == index } }

    /// The first set still to do, in order.
    var nextSetIndex: Int? { (0..<targetSets).first { record(at: $0)?.completedAt == nil } }

    /// What a set is planned at: its own edited values, else the last set logged before it so the
    /// next set is pre-filled with what was just done, else the prescription.
    func target(at index: Int) -> (weightKg: Double, reps: Int) {
        if let planned = record(at: index) { return (planned.weightKg, planned.reps) }
        if let previous = completedSets.last(where: { $0.index < index }) { return (previous.weightKg, previous.reps) }
        return (prescribedWeightKg ?? max(0, exercise?.startingWeightKg ?? 0), repLower)
    }

    /// The ramp to the first working set, so changing that set's weight moves the warm-ups with it.
    var warmUps: [WarmUpSet] {
        guard let exercise else { return [] }
        return WarmUp.sets(for: exercise, workingWeightKg: target(at: 0).weightKg)
    }

    /// What the engine needs to progress this movement next time.
    var historyEntry: ExerciseHistoryEntry? {
        // Each set is read once before sorting: across a long history, model reads are the cost.
        let performed = sets
            .map { (index: $0.index, isLogged: $0.completedAt != nil, set: PerformedSet(weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir)) }
            .filter { $0.isLogged && $0.set.reps > 0 }
            .sorted { $0.index < $1.index }
            .map(\.set)
        guard !performed.isEmpty, let date = session?.completedAt ?? session?.date else { return nil }
        return ExerciseHistoryEntry(exerciseID: exerciseID, date: date, targetReps: repRange, targetRIR: targetRIR, sets: performed)
    }
}

@Model
final class SetRecord {
    var index: Int
    var weightKg: Double
    var reps: Int
    /// Asked only on a movement's final set; `nil` on the sets before it.
    var rir: Int?
    var completedAt: Date?
    var exercise: PlannedExercise?

    init(index: Int, weightKg: Double, reps: Int, rir: Int? = nil) {
        self.index = index
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
    }
}
