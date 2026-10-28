import Foundation
import HealthKit
import Observation
import SwiftData
import TrainingEngine

/// Reads runs, yoga and strength workouts from Apple Health and completes Cadence sessions
/// from them, and saves finished strength sessions back as workouts with the effort rated when
/// they finished. Duration and distance come from the workout; effort comes from the Workout
/// Effort Score the athlete rates in Fitness (1 to 10), falling back to the estimated score. Heart rate gives each workout's average and the
/// max and resting figures that set the run zones; HRV, resting heart rate and sleep give the day's recovery.
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
        let averageHeartRate: Double?
        let activeKilocalories: Double?
        /// The Cadence session the workout belongs to: set on workouts Cadence saved and on those its watch app recorded.
        let externalID: UUID?
        /// Saved by Cadence from a finished strength session rather than recorded by a watch.
        let isOwn: Bool

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
    private var activeEnergyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private var restingHeartRateType: HKQuantityType { HKQuantityType(.restingHeartRate) }
    private var hrvType: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    private var readTypes: Set<HKObjectType> {
        [workoutType, effortType, estimatedEffortType, distanceType, activeEnergyType, bodyMassType, heartRateType, restingHeartRateType, hrvType, sleepType, HKCharacteristicType(.dateOfBirth)]
    }

    private var shareTypes: Set<HKSampleType> { [workoutType, activeEnergyType, effortType] }

    var isAvailable: Bool { state != .unavailable }

    static let enabledKey = "healthSyncEnabled"
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { state = .unavailable; return }
        state = .requesting
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
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
            HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining),
            HKQuery.predicateForWorkouts(with: .functionalStrengthTraining),
        ])
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, activities])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(combined)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = try await descriptor.result(for: store)

        var results: [Workout] = []
        for workout in workouts {
            let modality: Modality = switch workout.workoutActivityType {
            case .running: .running
            case .yoga: .yoga
            default: .strength
            }
            let distance = workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
            let (effort, estimated) = try await effortScore(for: workout)
            let heartRate = workout.statistics(for: heartRateType)?.averageQuantity()?.doubleValue(for: beatsPerMinute)
            let energy = workout.statistics(for: activeEnergyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let external = (workout.metadata?[HKMetadataKeyExternalUUID] as? String).flatMap(UUID.init(uuidString:))
            results.append(Workout(
                id: workout.uuid, modality: modality, start: workout.startDate, end: workout.endDate, distanceKm: distance,
                effort: effort, effortIsEstimated: estimated, averageHeartRate: heartRate, activeKilocalories: energy,
                externalID: external, isOwn: isOwn(workout)
            ))
        }
        return results
    }

    private func isOwn(_ workout: HKWorkout) -> Bool {
        workout.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier
    }

    private func storedWorkout(id: String) async throws -> HKWorkout? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: uuid))], sortDescriptors: [], limit: 1)
        return try await descriptor.result(for: store).first
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

    /// Max and resting heart rate for zones. Max blends the robust observed peak over six months
    /// with the age prediction; resting is the median of the last two weeks of daily readings.
    func heartRateFigures() async throws -> (maximum: Int?, resting: Int?) {
        let now = Date.now
        let sixMonths = Calendar.current.date(byAdding: .month, value: -6, to: now) ?? now
        let peaks = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: heartRateType, predicate: HKQuery.predicateForSamples(withStart: sixMonths, end: now)),
            options: .discreteMax,
            anchorDate: Calendar.current.startOfDay(for: now),
            intervalComponents: DateComponents(day: 1)
        )
        let dailyPeaks = try await peaks.result(for: store).statistics().compactMap { $0.maximumQuantity()?.doubleValue(for: beatsPerMinute) }
        let birth = try? store.dateOfBirthComponents().date
        let age = birth.flatMap { Calendar.current.dateComponents([.year], from: $0, to: now).year }

        let twoWeeks = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let resting = HKSampleQueryDescriptor(predicates: [.quantitySample(type: restingHeartRateType, predicate: HKQuery.predicateForSamples(withStart: twoWeeks, end: now))], sortDescriptors: [])
        let readings = try await resting.result(for: store).map { $0.quantity.doubleValue(for: beatsPerMinute) }.sorted()
        let median = readings.isEmpty ? nil : Int(readings[readings.count / 2].rounded())
        return (HeartRateZones.estimatedMaximum(dailyPeaks: dailyPeaks, age: age), median)
    }

    /// HRV, resting heart rate and time asleep, each over the window its recovery baseline needs.
    func recoveryReadings() async throws -> RecoveryReadings {
        func since(days: Int) -> NSPredicate {
            HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -days, to: .now), end: nil)
        }
        let hrv = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: hrvType, predicate: since(days: 62))], sortDescriptors: []).result(for: store)
        let resting = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: restingHeartRateType, predicate: since(days: 35))], sortDescriptors: []).result(for: store)
        let sleep = try await HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType, predicate: since(days: 33))], sortDescriptors: []).result(for: store)
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues
        return RecoveryReadings(
            hrv: hrv.map { .init(date: $0.startDate, value: $0.quantity.doubleValue(for: .secondUnit(with: .milli))) },
            restingHeartRate: resting.map { .init(date: $0.startDate, value: $0.quantity.doubleValue(for: beatsPerMinute)) },
            sleep: sleep.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value).map(asleep.contains) ?? false }
                .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        )
    }

    // MARK: Writing

    /// Saves a finished strength session to Apple Health as a Traditional Strength Training
    /// workout with an estimate of the active energy and the effort rated on finishing, so it
    /// shows in Fitness and counts toward the Move ring. A watch recording of the same day's
    /// lifting is linked instead and takes the rating, and finishing a reopened session replaces
    /// what Cadence saved the first time. A session Cadence's watch app recorded live waits for
    /// the watch to save its workout, and falls back to the estimate if it does not arrive.
    func record(_ session: TrainingSession, in context: ModelContext, coordinator: PlanCoordinator) async {
        guard isEnabled, session.modality == .strength, session.status == .completed,
              store.authorizationStatus(for: workoutType) == .sharingAuthorized else { return }
        let calendar = coordinator.calendar
        do {
            if let id = session.healthWorkoutID, let linked = try await storedWorkout(id: id) {
                if isOwn(linked) {
                    try await delete(linked)
                    session.healthWorkoutID = nil
                } else {
                    try await deleteOwnEffort(on: linked)
                }
            }
            // The watch recorded this session already, or ended its workout before it was finished here.
            func watchWorkouts() async throws -> [Workout] {
                try await workouts(since: calendar.startOfDay(for: session.date)).filter {
                    $0.modality == .strength && !$0.isOwn && calendar.isDate($0.start, inSameDayAs: session.date)
                }
            }
            var recorded = try await watchWorkouts()
            if session.recordedLive, !recorded.contains(where: { $0.externalID == session.id }), await arrival(ofWorkoutFor: session.id) {
                recorded = try await watchWorkouts()
            }
            let watch = recorded.first { $0.externalID == session.id }
                ?? recorded.first { $0.id.uuidString == session.healthWorkoutID }
                ?? recorded.first { workout in
                let id = workout.id.uuidString
                return ((try? context.fetchCount(FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.healthWorkoutID == id }))) ?? 0) == 0
            }
            if let watch {
                session.healthWorkoutID = watch.id.uuidString
                apply(watch, to: session)
                try context.save()
                if let workout = try await storedWorkout(id: watch.id.uuidString) {
                    try await deleteOwnEffort(on: workout)
                    try await rate(workout, as: session.rpe)
                }
                return
            }

            let logged = session.exercises.flatMap { exercise in
                exercise.completedSets.compactMap { set in set.completedAt.map { (exercise: exercise, set: set, at: $0) } }
            }
            guard let first = logged.min(by: { $0.at < $1.at }),
                  let interval = StrengthWorkoutRecord.interval(
                      setTimes: logged.map(\.at),
                      firstSetSeconds: Double(first.set.reps) * (first.exercise.exercise?.secondsPerRep ?? 3),
                      plannedMinutes: session.plannedMinutes
                  ) else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: interval.start)
            if store.authorizationStatus(for: activeEnergyType) == .sharingAuthorized {
                let kilocalories = StrengthWorkoutRecord.activeKilocalories(
                    bodyweightKg: coordinator.profile(in: context).bodyweightKg,
                    minutes: interval.duration / 60,
                    rpe: session.rpe ?? TrainingLoad.strengthSessionRPE(meanRIR: session.meanTargetRIR)
                )
                let energy = HKQuantitySample(type: activeEnergyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories), start: interval.start, end: interval.end)
                try await builder.addSamples([energy])
            }
            try await builder.addMetadata([HKMetadataKeyExternalUUID: session.id.uuidString])
            try await builder.endCollection(at: interval.end)
            guard let saved = try await builder.finishWorkout() else { return }
            session.healthWorkoutID = saved.uuid.uuidString
            try context.save()
            try await rate(saved, as: session.rpe)
        } catch {
            lastMessage = "Could not save the session to Apple Health: \(error.localizedDescription)"
        }
    }

    /// Waits for the workout Cadence's watch app saves for a session to reach this phone's Health
    /// store, which can take a little while after the watch ends it. True if it arrived.
    private func arrival(ofWorkoutFor sessionID: UUID, within seconds: Double = 90) async -> Bool {
        let stamped = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [sessionID.uuidString])
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout(stamped)], anchor: nil)
        let source = HKSource.default().bundleIdentifier
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { [store] in
                do {
                    for try await update in descriptor.results(for: store)
                    where update.addedSamples.contains(where: { $0.sourceRevision.source.bundleIdentifier != source }) {
                        return true
                    }
                } catch {}
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let arrived = await group.next() ?? false
            group.cancelAll()
            return arrived
        }
    }

    /// Takes back the workout Cadence saved when its session is reopened. A watch recording stays
    /// linked and loses only the effort Cadence gave it.
    func withdraw(_ session: TrainingSession, in context: ModelContext) async {
        guard let id = session.healthWorkoutID else { return }
        do {
            guard let linked = try await storedWorkout(id: id) else { return }
            guard isOwn(linked) else { try await deleteOwnEffort(on: linked); return }
            try await delete(linked)
            session.healthWorkoutID = nil
            try context.save()
        } catch {
            lastMessage = "Could not remove the session from Apple Health: \(error.localizedDescription)"
        }
    }

    private func delete(_ workout: HKWorkout) async throws {
        if store.authorizationStatus(for: activeEnergyType) == .sharingAuthorized {
            _ = try await store.deleteObjects(of: activeEnergyType, predicate: HKQuery.predicateForObjects(from: workout))
        }
        try await deleteOwnEffort(on: workout)
        try await store.delete(workout)
    }

    /// Relates a Workout Effort Score to the workout, so Fitness shows it as the rated effort.
    private func rate(_ workout: HKWorkout, as effort: Double?) async throws {
        guard let effort, store.authorizationStatus(for: effortType) == .sharingAuthorized else { return }
        let score = min(10, max(1, effort.rounded()))
        let sample = HKQuantitySample(type: effortType, quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score), start: workout.startDate, end: workout.endDate)
        _ = try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
    }

    /// Removes the effort Cadence related to a workout. Ratings from Fitness are left alone.
    private func deleteOwnEffort(on workout: HKWorkout) async throws {
        guard store.authorizationStatus(for: effortType) == .sharingAuthorized else { return }
        let own = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil),
            HKQuery.predicateForObjects(from: .default()),
        ])
        _ = try await store.deleteObjects(of: effortType, predicate: own)
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

    /// Pulls the last `days` of runs, yoga and strength workouts and reconciles them with the store:
    /// - a workout already synced updates its session,
    /// - a planned session of the same modality on that day is completed from the workout, except
    ///   a strength session with sets logged, which is still being logged and only takes the duration,
    /// - a completed session on that day without Health data (an import, a manual log) is enriched,
    /// - otherwise a new completed session is created.
    /// Workouts Cadence saved itself are skipped. A watch recording of a session Cadence already
    /// saved replaces Cadence's copy, so the session is not in Health twice, and takes its rating.
    @discardableResult
    func sync(days: Int = 90, in context: ModelContext, coordinator: PlanCoordinator) async -> SyncSummary {
        guard state == .ready || (isEnabled && state == .notRequested) else { return SyncSummary() }
        if state == .notRequested { state = .ready }
        // Heart rate and saving strength workouts arrived after the first permission request; ask once for anything new.
        if (try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)) == .shouldRequest {
            try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        }
        let calendar = coordinator.calendar
        let since = calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
        var summary = SyncSummary()
        do {
            if let mass = try await latestBodyMass() {
                let profile = coordinator.profile(in: context)
                let rounded = (mass.kilograms * 10).rounded() / 10
                // A weight entered by hand stands until Health has a reading taken after it.
                let newer = mass.date > (profile.bodyweightEnteredAt ?? .distantPast)
                if newer, profile.bodyweightFromHealthAt != mass.date || profile.bodyweightKg != rounded {
                    profile.bodyweightKg = rounded
                    profile.bodyweightFromHealthAt = mass.date
                    summary.bodyweightKg = rounded
                }
            }
            if let figures = try? await heartRateFigures() {
                let profile = coordinator.profile(in: context)
                var supplied = false
                if let maximum = figures.maximum, !profile.maxHeartRateSetByHand { profile.maxHeartRate = maximum; supplied = true }
                if let resting = figures.resting, !profile.restingHeartRateSetByHand { profile.restingHeartRate = resting; supplied = true }
                if supplied { profile.heartRateFromHealthAt = .now }
            }
            if let readings = try? await recoveryReadings() {
                coordinator.updateRecovery(RecoveryAnalysis.status(from: readings, asOf: .now, calendar: calendar), in: context)
            }
            let recorded = try await workouts(since: since).filter { !$0.isOwn }
            let recordedIDs = Set(recorded.map(\.id.uuidString))
            let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.date >= since }))) ?? []
            var replaced: [String] = []
            var rated: [(workoutID: String, effort: Double?)] = []
            for workout in recorded {
                let id = workout.id.uuidString
                if let existing = sessions.first(where: { $0.healthWorkoutID == id }) {
                    if apply(workout, to: existing) { summary.updated += 1 }
                    continue
                }
                // Cadence's watch app stamps the session it recorded. Otherwise free to match: no workout
                // yet, or only one Cadence saved, or one since deleted from Health.
                let stamped = workout.externalID.flatMap { external in sessions.first { $0.id == external } }
                let sameDay = stamped.map { [$0] } ?? sessions.filter {
                    $0.modality == workout.modality && calendar.isDate($0.date, inSameDayAs: workout.start)
                        && !($0.healthWorkoutID.map(recordedIDs.contains) ?? false) && $0.status != .skipped
                }
                func link(_ session: TrainingSession) {
                    if let previous = session.healthWorkoutID { replaced.append(previous) }
                    session.healthWorkoutID = id
                }
                if let planned = sameDay.first(where: { $0.status == .planned }) {
                    link(planned)
                    apply(workout, to: planned)
                    if planned.modality == .strength, planned.loggedSetCount > 0 {
                        summary.updated += 1
                    } else {
                        coordinator.complete(planned, at: workout.end, minutes: workout.minutes.rounded(), rpe: planned.rpe, distanceKm: planned.distanceKm, in: context)
                        summary.completed += 1
                    }
                } else if let done = sameDay.first(where: { $0.status == .completed }) {
                    link(done)
                    if apply(workout, to: done) { summary.updated += 1 }
                    // A lift logged here was rated when it finished; the watch's copy takes that rating. Imports stay out of Health.
                    if done.modality == .strength, done.loggedSetCount > 0, done.importKey == nil { rated.append((id, done.rpe)) }
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
            for id in replaced {
                if let workout = try await storedWorkout(id: id), isOwn(workout) { try await delete(workout) }
            }
            for (id, effort) in rated {
                guard let workout = try await storedWorkout(id: id) else { continue }
                try await deleteOwnEffort(on: workout)
                try await rate(workout, as: effort)
            }
            lastSync = .now
            lastMessage = summary.message
        } catch {
            lastMessage = "Apple Health sync failed: \(error.localizedDescription)"
        }
        return summary
    }

    /// Copies duration, distance, effort, heart rate and energy onto a session. Returns true if anything changed.
    @discardableResult
    private func apply(_ workout: Workout, to session: TrainingSession) -> Bool {
        var changed = false
        let minutes = workout.minutes.rounded()
        if session.actualMinutes != minutes { session.actualMinutes = minutes; changed = true }
        if let km = workout.distanceKm, session.modality == .running {
            let rounded = (km * 10).rounded() / 10
            if session.distanceKm != rounded { session.distanceKm = rounded; changed = true }
        }
        // A lifting session logged here was rated when it finished; Health holds a copy of that rating.
        let effortApplies = !(session.modality == .strength && session.loggedSetCount > 0)
        if let effort = workout.effort, effortApplies, session.rpe != effort { session.rpe = effort; changed = true }
        if let heartRate = workout.averageHeartRate, session.averageHeartRate != heartRate.rounded() { session.averageHeartRate = heartRate.rounded(); changed = true }
        if let energy = workout.activeKilocalories, session.activeKilocalories != energy.rounded() { session.activeKilocalories = energy.rounded(); changed = true }
        return changed
    }
}
