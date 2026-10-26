import Foundation
import SwiftData
import TrainingEngine

/// Eight weeks of plausible history so the load chart, progression and library have
/// something to show before the athlete has logged a single set. Deterministic.
enum SampleData {
    @MainActor
    static func seed(in context: ModelContext, coordinator: PlanCoordinator) {
        let calendar = coordinator.calendar
        var rng = SplitMix64(seed: 2026)
        let thisWeek = coordinator.weekStart(containing: .now)
        let profile = coordinator.profile(in: context)
        profile.bodyweightKg = 78

        var history: [ExerciseHistoryEntry] = []
        var upperFocus = FocusArea.chest
        var lowerFocus = FocusArea.quads
        var half = BodyHalf.upper
        var recent: [BodyHalf: Set<String>] = [:]
        // Latent one-rep max per movement. The simulated lifter is a little stronger than the
        // catalogue's conservative starts and gains about 1.5% a week, less on the deload.
        var strength: [String: Double] = [:]
        func latentMax(for exercise: Exercise) -> Double {
            if let known = strength[exercise.id] { return known }
            let base = exercise.equipment == .bodyweight ? profile.bodyweightKg : 0
            let value = Progression.estimatedOneRepMax(weightKg: exercise.startingWeightKg + base, reps: 8, rir: 2) * 1.08
            strength[exercise.id] = value
            return value
        }

        for weekOffset in stride(from: 8, through: 1, by: -1) {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * weekOffset, to: thisWeek) else { continue }
            // Running volume ramps gently; week 3 from the end is a deliberate deload.
            let ramp = weekOffset == 3 ? 0.8 : 1.0 + Double(8 - weekOffset) * 0.03
            let gain = weekOffset == 3 ? 1.004 : 1.015
            for key in strength.keys { strength[key]! *= gain }

            // Strength on Mon, Tue, Thu, Fri.
            for dayIndex in [0, 1, 3, 4] {
                let focus = half == .upper ? upperFocus : lowerFocus
                let generated = WorkoutGenerator.generate(StrengthSessionRequest(
                    half: half, focus: focus, recentExerciseIDs: recent[half] ?? [], history: history, variationSeed: weekOffset * 7 + dayIndex, bodyweightKg: profile.bodyweightKg))
                let date = calendar.date(byAdding: .hour, value: 7, to: calendar.date(byAdding: .day, value: dayIndex, to: weekStart)!)!
                let session = TrainingSession(date: date, modality: .strength, plannedMinutes: generated.estimatedMinutes.rounded(), weekStart: weekStart)
                session.half = half
                session.focus = focus
                session.status = .completed
                session.completedAt = date.addingTimeInterval(generated.estimatedMinutes * 60)
                session.actualMinutes = (generated.estimatedMinutes * (0.95 + rng.nextDouble() * 0.15)).rounded()

                for (order, prescription) in generated.prescriptions.enumerated() {
                    let planned = PlannedExercise(prescription: prescription, order: order)
                    let exercise = prescription.exercise
                    let base = exercise.equipment == .bodyweight ? profile.bodyweightKg : 0
                    let added = prescription.weightKg ?? max(0, exercise.startingWeightKg)
                    let total = added + base
                    let oneRepMax = latentMax(for: exercise)
                    // Reps to failure at this load, from the inverse of Epley.
                    let repsToFailure = max(1, 30 * (oneRepMax / max(total, 1) - 1))
                    var sets: [SetRecord] = []
                    for index in 0..<prescription.sets {
                        let fatigue = Double(index) * 0.6
                        let noise = Double(rng.nextInt(in: -1...1))
                        let available = Int((repsToFailure - fatigue + noise).rounded())
                        // Aim for the rep range, stop at the target RIR, be honest about what was left.
                        let reps = min(prescription.repRange.upperBound, max(prescription.repRange.lowerBound, available - prescription.targetRIR))
                        let rir = max(0, min(5, available - reps))
                        let set = SetRecord(index: index, weightKg: added, reps: reps, rir: rir)
                        set.completedAt = session.completedAt
                        sets.append(set)
                    }
                    planned.sets = sets
                    session.exercises.append(planned)
                }
                context.insert(session)
                session.rpe = TrainingLoad.strengthSessionRPE(meanRIR: session.loggedMeanRIR ?? 2)
                history += session.exercises.compactMap(\.historyEntry)
                recent[half] = Set(generated.prescriptions.map(\.exercise.id))
                if half == .upper { upperFocus = focus.next } else { lowerFocus = focus.next }
                half = half == .upper ? .lower : .upper
            }

            // Easy run Wednesday, long run Saturday, hot yoga Sunday.
            let easyMinutes = (35 * ramp / 5).rounded() * 5
            insertSimple(.running, kind: .easy, dayIndex: 2, minutes: easyMinutes, rpe: 4 + rng.nextDouble() * 0.8, distance: easyMinutes / 6.1, weekStart: weekStart, calendar: calendar, context: context)
            let longMinutes = (70 * ramp / 5).rounded() * 5
            insertSimple(.running, kind: .long, dayIndex: 5, minutes: longMinutes, rpe: 5.5 + rng.nextDouble(), distance: longMinutes / 6.3, weekStart: weekStart, calendar: calendar, context: context)
            insertSimple(.yoga, kind: nil, dayIndex: 6, minutes: 60, rpe: 4.5 + rng.nextDouble(), distance: nil, weekStart: weekStart, calendar: calendar, context: context)
        }

        profile.nextUpperFocus = upperFocus
        profile.nextLowerFocus = lowerFocus
        try? context.save()
    }

    @MainActor
    private static func insertSimple(_ modality: Modality, kind: RunKind?, dayIndex: Int, minutes: Double, rpe: Double, distance: Double?, weekStart: Date, calendar: Calendar, context: ModelContext) {
        let date = calendar.date(byAdding: .hour, value: 7, to: calendar.date(byAdding: .day, value: dayIndex, to: weekStart)!)!
        let session = TrainingSession(date: date, modality: modality, plannedMinutes: minutes, weekStart: weekStart)
        session.runKind = kind
        session.status = .completed
        session.completedAt = date.addingTimeInterval(minutes * 60)
        session.actualMinutes = minutes
        session.rpe = (rpe * 2).rounded() / 2
        session.distanceKm = distance.map { ($0 * 10).rounded() / 10 }
        context.insert(session)
    }

    @MainActor
    static func wipe(in context: ModelContext) {
        try? context.delete(model: TrainingSession.self)
        try? context.save()
    }
}

/// Small deterministic generator so sample data is identical on every device.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}
