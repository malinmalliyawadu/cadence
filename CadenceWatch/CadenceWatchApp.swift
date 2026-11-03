import HealthKit
import SwiftUI
import WatchKit

@main
struct CadenceWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(WorkoutManager.shared)
                .tint(Palette.accent)
                #if DEBUG
                .task { await WorkoutManager.shared.startDemo(arguments: ProcessInfo.processInfo.arguments) }
                #endif
        }
    }
}

/// Logging the first set on the phone launches the app here with a workout to start; a crash or
/// relaunch mid-session hands the running workout back.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WorkoutManager.shared.start(workoutConfiguration) }
    }

    func handleActiveWorkoutRecovery() {
        Task { await WorkoutManager.shared.recover() }
    }
}
