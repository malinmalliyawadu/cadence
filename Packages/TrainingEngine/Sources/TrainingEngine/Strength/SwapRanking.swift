import Foundation

/// One movement the athlete could swap in, with why it ranks where it does.
public struct SwapOption: Sendable, Hashable, Identifiable {
    public let exercise: Exercise
    public let score: Double
    /// Sessions logged on this movement.
    public let loggedSessions: Int
    /// "Same muscle and movement, logged 12 times". Empty when nothing stands out.
    public let reason: String

    public var id: String { exercise.id }
}

/// Orders every possible replacement for a movement. A direct substitute (same muscle, same
/// pattern, same role) comes first, then work for the session's focus, and movements the athlete
/// has logged rank above ones they have not, for the same reason the generator prefers them.
public enum SwapRanking {
    public static func options(
        replacing current: Exercise,
        focus: FocusArea?,
        excluding: Set<String> = [],
        equipment: Set<Equipment> = Set(Equipment.allCases),
        familiarity: [String: Int] = [:],
        library: [Exercise] = ExerciseLibrary.all
    ) -> [SwapOption] {
        let focusMuscles = focus?.muscles ?? []
        return library
            .filter { $0.half == current.half && $0.id != current.id && !excluding.contains($0.id) && equipment.contains($0.equipment) }
            .map { candidate in
                let sameMuscle = candidate.primary == current.primary
                let samePattern = candidate.pattern == current.pattern
                let servesFocus = focusMuscles.contains(candidate.primary)
                let logged = familiarity[candidate.id, default: 0]

                var score = 0.0
                if sameMuscle { score += 5 }
                if samePattern { score += 3 }
                if servesFocus { score += 3 } else if !focusMuscles.isDisjoint(with: candidate.secondary) { score += 1 }
                if candidate.role == current.role { score += 2 }
                score += Double(Set(candidate.muscles).intersection(current.secondary).count) * 0.5
                if logged > 0 { score += min(4, 1.5 + Double(logged) * 0.5) }

                return SwapOption(exercise: candidate, score: score, loggedSessions: logged,
                                  reason: reason(sameMuscle: sameMuscle, samePattern: samePattern, servesFocus: servesFocus, focus: focus, logged: logged))
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.exercise.name < $1.exercise.name }
    }

    private static func reason(sameMuscle: Bool, samePattern: Bool, servesFocus: Bool, focus: FocusArea?, logged: Int) -> String {
        var parts: [String] = []
        switch (sameMuscle, samePattern) {
        case (true, true): parts.append("same muscle and movement")
        case (true, false): parts.append("same muscle")
        case (false, true): parts.append("same movement")
        case (false, false): break
        }
        if servesFocus, let focus, !sameMuscle { parts.append("trains your \(focus.displayName.lowercased()) focus") }
        if logged > 0 { parts.append(logged == 1 ? "logged once" : "logged \(logged) times") }
        guard let first = parts.first else { return "" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: ", ")
    }
}
