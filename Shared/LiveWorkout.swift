import Foundation
import TrainingEngine

/// A set still to do, as the watch and the Live Activity show it.
struct LiveSet: Codable, Hashable, Sendable {
    /// The movement the set belongs to.
    var movement: String
    /// "Set 3 of 4".
    var setLabel: String
    /// "60 kg × 8".
    var target: String
}

/// The rest before a set: the countdown and the set it leads to. The rest Live Activity's state,
/// and what the watch counts down during a live workout.
struct RestDisplay: Codable, Hashable, Sendable {
    var timer: RestTimer
    var movement: String
    var setLabel: String
    var target: String

    var set: LiveSet { LiveSet(movement: movement, setLabel: setLabel, target: target) }
}

/// How much one tap of plus or minus changes the rest, everywhere it can be changed.
enum RestTimerStep {
    static let seconds: Double = 30
}

/// What the watch measures during a live workout, sent to the phone as it comes in.
struct LiveMetrics: Codable, Hashable, Sendable {
    /// The latest reading, beats per minute.
    var heartRate: Double?
    var averageHeartRate: Double?
    var activeKilocalories: Double?
}

/// What the phone and the watch tell each other during a live strength workout. The watch records
/// it and mirrors the session to the phone; these go both ways over the mirrored session.
enum LiveWorkoutMessage: Codable, Hashable, Sendable {
    // Phone to watch
    /// The session being logged, so the watch can title it and stamp the saved workout with its ID.
    case session(id: UUID, title: String)
    /// The next set to do, nil once every set is logged.
    case next(LiveSet?)
    /// The rest running on the phone, nil when it ends or is skipped.
    case rest(RestDisplay?)
    /// The session was finished on the phone: end and save the workout.
    case finish
    /// The session was skipped or every set undone: end without saving.
    case discard

    // Watch to phone
    case metrics(LiveMetrics)
    case adjustRest(seconds: Double)
    case skipRest

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    init(data: Data) throws { self = try JSONDecoder().decode(Self.self, from: data) }
}
