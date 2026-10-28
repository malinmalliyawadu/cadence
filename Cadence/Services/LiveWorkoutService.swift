import Foundation
import HealthKit
import Observation
import SwiftData
import TrainingEngine

/// The strength workout the watch records, mirrored here. Logging the first set launches the watch
/// app with a workout to start; starting one on the watch links it to today's session. While it runs
/// the watch sends heart rate and energy, and this tells it the next set, the rest before it, and
/// when the session is finished or skipped. The watch saves the workout to Health stamped with the
/// session's ID, and `HealthKitService` links it from there. With no watch, nothing changes: the
/// session is saved with an estimate when it finishes.
@MainActor
@Observable
final class LiveWorkoutService: NSObject {
    /// The session the watch is recording.
    private(set) var sessionID: UUID?
    private(set) var metrics = LiveMetrics()
    private(set) var isLive = false

    private let store = HKHealthStore()
    private let health: HealthKitService
    private let rest: RestTimerService
    private var mirrored: HKWorkoutSession?
    /// Asked the watch to start for this session and waiting for it to mirror.
    private var pendingID: UUID?
    /// Sessions the watch could not start for: no watch, or Cadence is not on it. Not asked again until relaunch.
    private var unavailable: Set<UUID> = []
    private var context: ModelContext?
    private var coordinator: PlanCoordinator?

    init(health: HealthKitService, rest: RestTimerService) {
        self.health = health
        self.rest = rest
        super.init()
        // Set at launch, as HealthKit asks, so a workout started on the watch reaches the app even when it was not running.
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
        rest.onChange = { [weak self] state in self?.send(.rest(state)) }
    }

    /// The store and coordinator, for linking a workout started on the watch to today's session.
    func attach(context: ModelContext, coordinator: PlanCoordinator) {
        self.context = context
        self.coordinator = coordinator
    }

    func isRecording(_ session: TrainingSession) -> Bool { isLive && sessionID == session.id }

    // MARK: From the session screen

    /// Called whenever the logged sets change: the first set starts the watch, every change tells it the next set.
    func progress(in session: TrainingSession) {
        if isRecording(session) {
            send(.next(Self.nextSet(in: session)))
            return
        }
        guard session.modality == .strength, session.status == .planned, session.loggedSetCount > 0,
              health.isEnabled, mirrored == nil, pendingID == nil, !unavailable.contains(session.id) else { return }
        let id = session.id
        pendingID = id
        Task {
            do {
                try await store.startWatchApp(toHandle: Self.strength)
            } catch {
                unavailable.insert(id)
                if pendingID == id { pendingID = nil }
            }
        }
        // The request can go unanswered when the watch is asleep or out of reach; the next set asks again.
        Task {
            try? await Task.sleep(for: .seconds(30))
            if pendingID == id, mirrored == nil { pendingID = nil }
        }
    }

    /// The session was finished here: the watch ends and saves the workout.
    func finish(_ session: TrainingSession) {
        guard isRecording(session) else { return }
        send(.finish)
    }

    /// The session was skipped: the watch ends without saving.
    func discard(_ session: TrainingSession) {
        if pendingID == session.id { pendingID = nil }
        guard isRecording(session) else { return }
        send(.discard)
    }

    // MARK: The mirrored workout

    private func adopt(_ session: HKWorkoutSession) {
        session.delegate = self
        mirrored = session
        isLive = true
        metrics = LiveMetrics()
        // The watch taps the wrist when rest is over; the phone's alert would be a second tap.
        RestAlarm.isWatchAlerting = true
        RestAlarm.cancel()
        let id = pendingID ?? todaysSession()?.id
        pendingID = nil
        guard let id, let training = trainingSession(id) else { return }
        sessionID = id
        training.recordedLive = true
        try? context?.save()
        send(.session(id: id, title: "\(training.title), \(training.subtitle.lowercased())"))
        send(.next(Self.nextSet(in: training)))
        send(.rest(rest.isResting(in: training) ? rest.state : nil))
    }

    private func didEnd() {
        mirrored = nil
        isLive = false
        RestAlarm.isWatchAlerting = false
        if let state = rest.state { Task { await RestAlarm.schedule(state) } }
    }

    private func receive(_ message: LiveWorkoutMessage) {
        switch message {
        case .metrics(let metrics):
            self.metrics = metrics
        case .adjustRest(let seconds):
            rest.adjust(by: seconds)
        case .skipRest:
            rest.stop()
        case .session, .next, .rest, .finish, .discard:
            break
        }
    }

    private func send(_ message: LiveWorkoutMessage) {
        guard let mirrored, let data = try? message.encoded() else { return }
        Task { try? await mirrored.sendToRemoteWorkoutSession(data: data) }
    }

    // MARK: Lookups

    private static var strength: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    private func trainingSession(_ id: UUID) -> TrainingSession? {
        try? context?.fetch(FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.id == id })).first
    }

    /// Today's strength session still to do, for a workout started on the watch.
    private func todaysSession() -> TrainingSession? {
        guard let context, let calendar = coordinator?.calendar else { return nil }
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .now
        let planned = SessionStatus.planned.rawValue
        let strength = Modality.strength.rawValue
        let today = (try? context.fetch(FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.statusRaw == planned && $0.modalityRaw == strength },
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        return today.first { !$0.exercises.isEmpty }
    }

    static func nextSet(in session: TrainingSession) -> LiveSet? {
        guard let exercise = session.orderedExercises.first(where: { !$0.isComplete }), let index = exercise.nextSetIndex else { return nil }
        return LiveSet(exercise, set: index)
    }
}

extension LiveWorkoutService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in didEnd() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap { try? LiveWorkoutMessage(data: $0) }
        Task { @MainActor in messages.forEach(receive) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor in didEnd() }
    }
}

extension LiveSet {
    /// A set as the rest card, the Live Activity and the watch show it: "Set 3 of 4", "60 kg × 8".
    init(_ exercise: PlannedExercise, set index: Int) {
        let target = exercise.target(at: index)
        self.init(movement: exercise.name, setLabel: "Set \(index + 1) of \(exercise.targetSets)", target: "\(Format.kg(target.weightKg)) kg × \(target.reps)")
    }
}
