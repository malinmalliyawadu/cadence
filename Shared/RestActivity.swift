import ActivityKit
import Foundation
import TrainingEngine
import UserNotifications

/// The rest between sets as a Live Activity, on the Lock Screen and in the Dynamic Island.
/// Shared by the app, which starts it, and the widget extension, which draws it.
struct RestActivityAttributes: ActivityAttributes {
    typealias ContentState = RestDisplay

    let sessionID: UUID
}

/// The few things done to a running rest from outside the app's screens: the Live Activity's
/// buttons and the app catching up after a relaunch. Starting one is the app's job.
enum RestActivity {
    /// What the app needs to pick a rest back up.
    struct Snapshot: Sendable {
        let id: String
        let sessionID: UUID
        let state: RestActivityAttributes.ContentState
    }

    static var current: Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    static var snapshot: Snapshot? {
        current.map { Snapshot(id: $0.id, sessionID: $0.attributes.sessionID, state: $0.content.state) }
    }

    static func update(_ activity: Activity<RestActivityAttributes>, to state: RestActivityAttributes.ContentState) async {
        await activity.update(ActivityContent(state: state, staleDate: state.timer.endsAt))
        await RestAlarm.schedule(state)
    }

    static func adjust(by seconds: Double) async {
        guard let activity = current else { return }
        var state = activity.content.state
        state.timer = state.timer.adjusted(by: seconds)
        await update(activity, to: state)
    }

    static func endAll() async {
        RestAlarm.cancel()
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// The notification that says rest is over, for when the phone is in a pocket.
enum RestAlarm {
    static let identifier = "rest-over"
    /// While the watch records the session it taps the wrist itself, so the phone stays quiet.
    @MainActor static var isWatchAlerting = false

    static func schedule(_ state: RestActivityAttributes.ContentState) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard await !isWatchAlerting else { return }
        let remaining = state.timer.remaining()
        guard remaining >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "\(state.movement), \(state.setLabel.lowercased()) at \(state.target)."
        // The chime the app plays itself when rest runs out with it open (SoundEffects).
        content.sound = UNNotificationSound(named: UNNotificationSoundName("rest-over.caf"))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
