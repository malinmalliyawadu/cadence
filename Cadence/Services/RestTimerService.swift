import ActivityKit
import Foundation
import Observation
import TrainingEngine
import UIKit
import UserNotifications

/// The rest between sets. Logging a set starts it, sized by the engine for the next set's
/// movement; it shows on the session screen, as a Live Activity on the Lock Screen and in the
/// Dynamic Island, and as a notification when it runs out. The Live Activity's buttons change
/// it while the app is in the background, so the app reads it back on coming to the front.
@MainActor
@Observable
final class RestTimerService {
    private(set) var state: RestActivityAttributes.ContentState? {
        didSet { if state != oldValue { onChange?(state) } }
    }
    /// Told whenever the rest changes, so a live workout on the watch counts down the same rest.
    var onChange: ((RestActivityAttributes.ContentState?) -> Void)?
    private(set) var sessionID: UUID?
    /// Whether the session screen is showing the rest, so the notification stays quiet there.
    var isOnScreen = false {
        didSet { RestAlarmPresenter.isOnScreen = isOnScreen }
    }

    private var activityID: String?
    private var feedback: Task<Void, Never>?
    private let presenter = RestAlarmPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    func isResting(in session: TrainingSession) -> Bool { state != nil && sessionID == session.id }

    func start(seconds: Double, before exercise: PlannedExercise, set index: Int, in session: TrainingSession) {
        let set = LiveSet(exercise, set: index)
        let state = RestActivityAttributes.ContentState(timer: RestTimer(seconds: seconds), movement: set.movement, setLabel: set.setLabel, target: set.target)
        self.state = state
        sessionID = session.id
        scheduleFeedback()
        Task {
            await present(state, for: session.id)
            // Scheduled before the athlete answered, the alarm was dropped: schedule it again.
            if await requestAlertsOnce(), self.state == state { await RestAlarm.schedule(state) }
        }
    }

    func adjust(by seconds: Double) {
        guard var state else { return }
        state.timer = state.timer.adjusted(by: seconds)
        self.state = state
        scheduleFeedback()
        Task { await present(state, for: sessionID) }
    }

    func stop() {
        state = nil
        sessionID = nil
        activityID = nil
        feedback?.cancel()
        Task { await RestActivity.endAll() }
    }

    func stop(for session: TrainingSession) {
        if sessionID == session.id { stop() }
    }

    /// Catches up with the Live Activity: its buttons may have added rest or skipped it, the
    /// athlete may have swiped it away, or the app may have been relaunched mid-rest. A rest
    /// long over by then is ended rather than brought back.
    func sync() {
        guard let snapshot = RestActivity.snapshot else {
            if activityID != nil { stop() }
            return
        }
        if snapshot.state.timer.overtime() > 10 * 60 {
            stop()
            return
        }
        state = snapshot.state
        sessionID = snapshot.sessionID
        activityID = snapshot.id
        scheduleFeedback()
    }

    private func present(_ state: RestActivityAttributes.ContentState, for sessionID: UUID?) async {
        guard let sessionID, self.state == state else { return }
        let id = await RestActivity.show(state, sessionID: sessionID)
        if self.state == state { activityID = id }
    }

    /// A tap on the wrist when rest runs out with the app open. In the background the
    /// notification does this.
    private func scheduleFeedback() {
        feedback?.cancel()
        guard let state else { return }
        let remaining = state.timer.remaining()
        guard remaining > 0 else { return }
        feedback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, self?.state?.timer == state.timer else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private static let askedKey = "restAlertsRequested"

    /// Asked the first time a rest starts, when it is obvious what the alert is for. True when
    /// the athlete has just allowed alerts.
    private func requestAlertsOnce() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.askedKey) else { return false }
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

extension RestActivity {
    /// Shows a rest: updates the session's Live Activity, or ends any other and starts a new
    /// one. The alarm is scheduled either way, so it rings with Live Activities turned off.
    /// Returns the activity's identifier.
    static func show(_ state: RestActivityAttributes.ContentState, sessionID: UUID) async -> String? {
        if let activity = current, activity.attributes.sessionID == sessionID {
            await update(activity, to: state)
            return activity.id
        }
        await endAll()
        await RestAlarm.schedule(state)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        do {
            let activity = try Activity.request(
                attributes: RestActivityAttributes(sessionID: sessionID),
                content: ActivityContent(state: state, staleDate: state.timer.endsAt)
            )
            return activity.id
        } catch {
            print("Could not start the rest Live Activity: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Shows the rest-over notification while the app is open: as a sound alone on the session
/// screen, which already says rest is over, and as a banner anywhere else in the app.
private final class RestAlarmPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    @MainActor static var isOnScreen = false

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier == RestAlarm.identifier else { return [.banner, .sound] }
        return await Self.isOnScreen ? [.sound] : [.banner, .sound]
    }
}
