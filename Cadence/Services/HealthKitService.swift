import Foundation
import HealthKit
import Observation
import SwiftData
import TrainingEngine

/// Reads runs and yoga from Apple Health and completes Cadence sessions from them.
/// Duration and distance come from the workout; effort comes from the Workout Effort
/// Score the athlete rates in Fitness (1 to 10), falling back to the estimated score.
@MainActor
@Observable
final class HealthKitService {
    struct Workout: Sendable, Hashable, Identifiable {
        let id: UUID
        let modality: Modality
        let start: Date
        let end: Date
        let distanceKm: Double?
        let effort: Double?
        let effortIsEstimated: Bool

        var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    enum State: Equatable {
        case unavailable, notRequested, requesting, denied, ready
    }

    private(set) var state: State = HKHealthStore.isHealthDataAvailable() ? .notRequested : .unavailable
    private(set) var lastSync: Date?
    private(set) var lastMessage: String?

    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()
    private var effortType: HKQuantityType { HKQuantityType(.workoutEffortScore) }
    private var estimatedEffortType: HKQuantityType { HKQuantityType(.estimatedWorkoutEffortScore) }
    private var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }

    var isAvailable: Bool { state != .unavailable }

    static let enabledKey = "healthSyncEnabled"
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { state = .unavailable; return }
        state = .requesting
        let read: Set<HKObjectType> = [workoutType, effortType, estimatedEffortType, distanceType, bodyMassType]
        #if DEBUG
        let share: Set<HKSampleType> = [workoutType, effortType, distanceType, bodyMassType]
        #else
        let share: Set<HKSampleType> = []
        #endif
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            // Read permission is never reported directly; a request that completes is as good as it gets.
            state = .ready
            isEnabled = true
        } catch {
            state = .denied
            lastMessage = error.localizedDescription
        }
    }

    // MARK: Reading

    func workouts(since start: Date) async throws -> [Workout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let activities = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForWorkouts(with: .yoga),
        ])
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, activities])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(combined)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = try await descriptor.result(for: store)

        var results: [Workout] = []
        for workout in workouts {
            let modality: Modality = workout.workoutActivityType == .yoga ? .yoga : .running
            let distance = workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
            let (effort, estimated) = try await effortScore(for: workout)
            results.append(Workout(id: workout.uuid, modality: modality, start: workout.startDate, end: workout.endDate, distanceKm: distance, effort: effort, effortIsEstimated: estimated))
        }
        return results
    }

    private func effortScore(for workout: HKWorkout) async throws -> (Double?, Bool) {
        let related = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        let rated = HKSampleQueryDescriptor(predicates: [.quantitySample(type: effortType, predicate: related)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        if let sample = try await rated.result(for: store).first {
            return (sample.quantity.doubleValue(for: .appleEffortScore()), false)
        }
        let estimated = HKSampleQueryDescriptor(predicates: [.quantitySample(type: estimatedEffortType, predicate: related)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        if let sample = try await estimated.result(for: store).first {
            return (sample.quantity.doubleValue(for: .appleEffortScore()), true)
        }
        return (nil, false)
    }

    /// The most recent bodyweight in Health, if any.
    func latestBodyMass() async throws -> (kilograms: Double, date: Date)? {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: bodyMassType)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.startDate)
    }

    // MARK: Syncing

    struct SyncSummary: Equatable {
        var completed = 0
        var created = 0
        var updated = 0
        var bodyweightKg: Double?
        var message: String {
            var parts: [String] = []
            if completed > 0 { parts.append("\(completed) planned session\(completed == 1 ? "" : "s") completed") }
            if created > 0 { parts.append("\(created) added") }
            if updated > 0 { parts.append("\(updated) updated") }
            var text = parts.isEmpty ? "Nothing new in Apple Health." : parts.joined(separator: ", ") + " from Apple Health."
            if let bodyweightKg { text += " Bodyweight \(Format.kg(bodyweightKg)) kg." }
            return text
        }
    }

    /// Pulls the last `days` of runs and yoga and reconciles them with the store:
    /// - a workout already synced updates its session,
    /// - a planned session of the same modality on that day is completed from the workout,
    /// - a completed session on that day without Health data (an import, a manual log) is enriched,
    /// - otherwise a new completed session is created.
    @discardableResult
    func sync(days: Int = 90, in context: ModelContext, coordinator: PlanCoordinator) async -> SyncSummary {
        guard state == .ready || (isEnabled && state == .notRequested) else { return SyncSummary() }
        if state == .notRequested { state = .ready }
        let calendar = coordinator.calendar
        let since = calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
        var summary = SyncSummary()
        do {
            if let mass = try await latestBodyMass() {
                let profile = coordinator.profile(in: context)
                let rounded = (mass.kilograms * 10).rounded() / 10
                if profile.bodyweightFromHealthAt != mass.date || profile.bodyweightKg != rounded {
                    profile.bodyweightKg = rounded
                    profile.bodyweightFromHealthAt = mass.date
                    summary.bodyweightKg = rounded
                }
            }
            let workouts = try await workouts(since: since)
            let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.date >= since }))) ?? []
            for workout in workouts {
                let id = workout.id.uuidString
                if let existing = sessions.first(where: { $0.healthWorkoutID == id }) {
                    if apply(workout, to: existing) { summary.updated += 1 }
                    continue
                }
                let sameDay = sessions.filter { $0.modality == workout.modality && calendar.isDate($0.date, inSameDayAs: workout.start) && $0.healthWorkoutID == nil && $0.status != .skipped }
                if let planned = sameDay.first(where: { $0.status == .planned }) {
                    planned.healthWorkoutID = id
                    apply(workout, to: planned)
                    coordinator.complete(planned, minutes: workout.minutes.rounded(), rpe: planned.rpe, distanceKm: planned.distanceKm, in: context)
                    summary.completed += 1
                } else if let done = sameDay.first(where: { $0.status == .completed }) {
                    done.healthWorkoutID = id
                    if apply(workout, to: done) { summary.updated += 1 }
                } else {
                    let minutes = workout.minutes.rounded()
                    let session = TrainingSession(date: workout.start, modality: workout.modality, plannedMinutes: minutes, weekStart: coordinator.weekStart(containing: workout.start))
                    session.healthWorkoutID = id
                    session.status = .completed
                    session.completedAt = workout.end
                    session.actualMinutes = minutes
                    if workout.modality == .running {
                        session.runKind = (workout.distanceKm ?? 0) >= 14 ? .long : .easy
                    }
                    apply(workout, to: session)
                    context.insert(session)
                    summary.created += 1
                }
            }
            try context.save()
            lastSync = .now
            lastMessage = summary.message
        } catch {
            lastMessage = "Apple Health sync failed: \(error.localizedDescription)"
        }
        return summary
    }

    /// Copies duration, distance and effort onto a session. Returns true if anything changed.
    @discardableResult
    private func apply(_ workout: Workout, to session: TrainingSession) -> Bool {
        var changed = false
        let minutes = workout.minutes.rounded()
        if session.actualMinutes != minutes { session.actualMinutes = minutes; changed = true }
        if let km = workout.distanceKm, session.modality == .running {
            let rounded = (km * 10).rounded() / 10
            if session.distanceKm != rounded { session.distanceKm = rounded; changed = true }
        }
        if let effort = workout.effort, session.rpe != effort { session.rpe = effort; changed = true }
        return changed
    }

    // MARK: Development helpers

    #if DEBUG
    /// Writes a run and a yoga class into Health so the sync path can be exercised in the simulator.
    func writeSampleWorkouts() async {
        guard state == .ready else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        do {
            // A 48 minute run this morning, 8.2 km, rated 5.
            let runStart = calendar.date(byAdding: .hour, value: 6, to: today)!
            let runEnd = runStart.addingTimeInterval(48 * 60)
            try await writeWorkout(.running, start: runStart, end: runEnd, distanceKm: 8.2, effort: 5)
            // A 60 minute hot yoga class yesterday evening, rated 4.
            let yogaStart = calendar.date(byAdding: .hour, value: -6, to: today)!
            let yogaEnd = yogaStart.addingTimeInterval(60 * 60)
            try await writeWorkout(.yoga, start: yogaStart, end: yogaEnd, distanceKm: nil, effort: 4)
            // A bodyweight reading from this morning.
            let mass = HKQuantitySample(type: bodyMassType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 78.4), start: runStart, end: runStart)
            try await store.save(mass)
            lastMessage = "Wrote a sample run, yoga class and bodyweight to Health."
        } catch {
            lastMessage = "Could not write to Health: \(error.localizedDescription)"
        }
    }

    private func writeWorkout(_ activity: HKWorkoutActivityType, start: Date, end: Date, distanceKm: Double?, effort: Double) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        if let distanceKm {
            let quantity = HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: distanceKm)
            let sample = HKQuantitySample(type: distanceType, quantity: quantity, start: start, end: end)
            try await builder.addSamples([sample])
        }
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { return }
        let score = HKQuantitySample(type: effortType, quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: effort), start: end, end: end)
        try await store.relateWorkoutEffortSample(score, with: workout, activity: nil)
    }
    #endif
}
