import Foundation

/// The emphasis the athlete picks for a strength session. The generator gives the
/// focus area the first slot, an extra set on its compounds and an extra isolation
/// movement, while still training the rest of the half enough to maintain it.
public enum FocusArea: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    // Upper
    case chest, back, shoulders, arms
    // Lower
    case quads, posteriorChain, glutes

    public var id: String { rawValue }

    public var half: BodyHalf {
        switch self {
        case .chest, .back, .shoulders, .arms: .upper
        case .quads, .posteriorChain, .glutes: .lower
        }
    }

    public var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .quads: "Quads"
        case .posteriorChain: "Posterior chain"
        case .glutes: "Glutes"
        }
    }

    /// Muscle groups this focus is about. An exercise "serves" the focus when its primary is one of these.
    public var muscles: Set<MuscleGroup> {
        switch self {
        case .chest: [.chest]
        case .back: [.back]
        case .shoulders: [.shoulders]
        case .arms: [.biceps, .triceps]
        case .quads: [.quads]
        case .posteriorChain: [.hamstrings]
        case .glutes: [.glutes]
        }
    }

    /// Exercise IDs that make the best session opener for this focus, in preference order.
    public var preferredOpeners: [String] {
        switch self {
        case .chest: ["bb-bench", "db-incline-press"]
        case .back: ["pull-up", "bb-row"]
        case .shoulders: ["bb-ohp", "db-shoulder-press"]
        case .arms: ["cg-bench", "chin-up"]
        case .quads: ["bb-back-squat", "bb-front-squat", "hack-squat"]
        case .posteriorChain: ["bb-deadlift", "rdl"]
        case .glutes: ["hip-thrust", "rdl"]
        }
    }

    public static func areas(for half: BodyHalf) -> [FocusArea] {
        allCases.filter { $0.half == half }
    }

    /// The focus that follows this one when the athlete does not choose. Rotates through the half.
    public var next: FocusArea {
        let areas = FocusArea.areas(for: half)
        let index = areas.firstIndex(of: self) ?? 0
        return areas[(index + 1) % areas.count]
    }
}
