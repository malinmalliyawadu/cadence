import Foundation
import HealthKit
import Observation
import TrainingEngine
import WatchKit

/// Records a strength session on the wrist. Running a workout session is what makes the watch read
/// heart rate every few seconds and work out active energy from it; without one it samples every few
/// minutes. The session is mirrored to the phone, which logs the sets and tells the watch the next
/// one, the rest before it, and when the session is finished.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    enum Phase: Equatable {
        case idle, starting, running, paused, saving, ended
    }

    private(set) var phase: Phase = .idle
    private(set) var title = "Strength"
    private(set) var metrics = LiveMetrics()
    private(set) var next: LiveSet?
    private(set) var rest: RestDisplay?
    /// Whether the last workout was saved, and how long it ran, for the summary.
    private(set) var saved = false
    private(set) var duration: TimeInterval = 0
    private(set) var message: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The Cadence session this workout belongs to, stamped on the saved workout so the phone matches it exactly.
    private var sessionID: UUID?
    private var saveOnEnd = true
    private var alarm: Task<Void, Never>?

    nonisolated static let heartRateType = HKQuantityType(.heartRate)
    nonisolated static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    nonisolated private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    static var strength: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    var isActive: Bool { phase == .running || phase == .paused }

    /// Time the workout has run, less any pauses.
    func elapsed(at date: Date) -> TimeInterval { builder?.elapsedTime(at: date) ?? 0 }

    // MARK: Starting and ending

    func start(_ configuration: HKWorkoutConfiguration = WorkoutManager.strength) async {
        guard session == nil, phase == .idle || phase == .ended else { return }
        phase = .starting
        message = nil
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [Self.heartRateType, Self.activeEnergyType])
            // A workout recovered after a relaunch while access was being asked for is the one to keep.
            guard self.session == nil else { return }
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            adopt(session, builder)
            sessionID = nil
            title = "Strength"
            metrics = LiveMetrics()
            next = nil
            setRest(nil)
            saveOnEnd = true
            // The phone shows it live and logs the sets; without it the watch still records.
            try? await session.startMirroringToCompanionDevice()
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
        } catch {
            phase = .idle
            message = "Could not start the workout: \(error.localizedDescription)"
        }
    }

    /// Picks the workout back up after the app was relaunched mid-session.
    func recover() async {
        guard session == nil, let session = try? await store.recoverActiveWorkoutSession(), self.session == nil else { return }
        adopt(session, session.associatedWorkoutBuilder())
        phase = session.state == .paused ? .paused : .running
        try? await session.startMirroringToCompanionDevice()
    }

    private func adopt(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder) {
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the workout: saved to Health, or thrown away when the session was skipped on the phone.
    func end(saving: Bool) {
        guard let session, isActive else { return }
        saveOnEnd = saving
        phase = .saving
        session.stopActivity(with: .now)
    }

    func dismissSummary() {
        phase = .idle
        metrics = LiveMetrics()
    }

    private func didEnd(at date: Date) async {
        guard let builder else { return }
        setRest(nil)
        duration = builder.elapsedTime(at: date)
        do {
            try await builder.endCollection(at: date)
            if saveOnEnd {
                if let sessionID {
                    try await builder.addMetadata([HKMetadataKeyExternalUUID: sessionID.uuidString])
                }
                _ = try await builder.finishWorkout()
            } else {
                builder.discardWorkout()
            }
            saved = saveOnEnd
        } catch {
            saved = false
            message = "Could not save the workout: \(error.localizedDescription)"
        }
        session = nil
        self.builder = nil
        phase = saveOnEnd ? .ended : .idle
    }

    // MARK: Rest

    func addRest() {
        guard var rest else { return }
        rest.timer = rest.timer.adjusted(by: RestTimerStep.seconds)
        setRest(rest)
        send(.adjustRest(seconds: RestTimerStep.seconds))
    }

    func skipRest() {
        setRest(nil)
        send(.skipRest)
    }

    /// Shows the rest and taps the wrist when it runs out.
    private func setRest(_ display: RestDisplay?) {
        rest = display
        alarm?.cancel()
        guard let display, !display.timer.isOver() else { return }
        let remaining = display.timer.remaining()
        alarm = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, self?.rest?.timer == display.timer else { return }
            WKInterfaceDevice.current().play(.stop)
        }
    }

    // MARK: Messages

    private func receive(_ message: LiveWorkoutMessage) {
        switch message {
        case .session(let id, let title):
            sessionID = id
            self.title = title
        case .next(let set):
            next = set
        case .rest(let display):
            setRest(display)
        case .finish:
            end(saving: true)
        case .discard:
            end(saving: false)
        case .metrics, .adjustRest, .skipRest:
            break
        }
    }

    #if DEBUG
    /// Development convenience, since workouts do not mirror between simulators: `-demoWorkout` starts one
    /// and feeds it what the phone would send. `-demoRest` adds a rest; `-demoRestOver` one that has run out.
    func startDemo(arguments: [String]) async {
        guard arguments.contains("-demoWorkout") else { return }
        await start()
        receive(.session(id: UUID(), title: "Upper body, chest focus"))
        let set = LiveSet(movement: "Barbell Bench Press", setLabel: "Set 2 of 4", target: "60 kg × 8")
        receive(.next(set))
        let seconds: Double? = arguments.contains("-demoRest") ? 150 : arguments.contains("-demoRestOver") ? 0 : nil
        if let seconds {
            let timer = RestTimer(startedAt: .now.addingTimeInterval(seconds > 0 ? -40 : -170), seconds: 150)
            receive(.rest(RestDisplay(timer: timer, movement: set.movement, setLabel: set.setLabel, target: set.target)))
        }
    }
    #endif

    private func send(_ message: LiveWorkoutMessage) {
        guard let session, let data = try? message.encoded() else { return }
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    private func update(_ metrics: LiveMetrics) {
        self.metrics = metrics
        send(.metrics(metrics))
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: phase = .running
            case .paused: phase = .paused
            case .stopped: session?.end()
            case .ended: await didEnd(at: date)
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let text = error.localizedDescription
        Task { @MainActor in message = "The workout stopped: \(text)" }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap { try? LiveWorkoutMessage(data: $0) }
        Task { @MainActor in messages.forEach(receive) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        // The watch keeps recording; the phone picks the workout up from Health when it is finished.
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(Self.heartRateType) || collectedTypes.contains(Self.activeEnergyType) else { return }
        let heartRate = workoutBuilder.statistics(for: Self.heartRateType)
        let energy = workoutBuilder.statistics(for: Self.activeEnergyType)
        let metrics = LiveMetrics(
            heartRate: heartRate?.mostRecentQuantity()?.doubleValue(for: Self.beatsPerMinute),
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: Self.beatsPerMinute),
            activeKilocalories: energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        )
        Task { @MainActor in update(metrics) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
