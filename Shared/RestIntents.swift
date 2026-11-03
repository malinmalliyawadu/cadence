import AppIntents
import Foundation

/// The Live Activity's buttons. A Live Activity intent runs in the app's process, so the app
/// picks up the change when it next comes to the front.
struct AddRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 30 seconds of rest"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestActivity.adjust(by: RestTimerStep.seconds)
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip the rest"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestActivity.endAll()
        return .result()
    }
}
