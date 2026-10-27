import SwiftData
import SwiftUI
import TrainingEngine

/// Everything the athlete can change about a session before starting it: the focus, the
/// half, which day it happens (another session's, or a rest day's), or a run's type. Hidden
/// once something has been logged.
struct ChangeSessionMenu: View {
    let session: TrainingSession
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    var isAvailable: Bool { session.status == .planned && session.loggedSetCount == 0 }

    var body: some View {
        Menu {
            if session.modality == .strength, let half = session.half {
                Section("Focus") {
                    ForEach(FocusArea.areas(for: half)) { focus in
                        Button {
                            coordinator.regenerate(session, half: half, focus: focus, in: context)
                        } label: {
                            if focus == session.focus { Label(focus.displayName, systemImage: "checkmark") } else { Text(focus.displayName) }
                        }
                    }
                }
                let other: BodyHalf = half == .upper ? .lower : .upper
                Menu("Switch to \(other.displayName.lowercased()) body") {
                    ForEach(FocusArea.areas(for: other)) { focus in
                        Button("\(focus.displayName) focus") { coordinator.regenerate(session, half: other, focus: focus, in: context) }
                    }
                }
            }
            if session.modality == .running {
                Section("Run type") {
                    ForEach(RunKind.allCases, id: \.self) { kind in
                        Button {
                            coordinator.changeRunKind(session, to: kind, in: context)
                        } label: {
                            if kind == session.runKind { Label(kind.displayName, systemImage: "checkmark") } else { Text(kind.displayName) }
                        }
                    }
                }
            }
            // Other sessions and rest days, in day order. Nil is a rest day.
            let targets: [(date: Date, other: TrainingSession?)] = (coordinator.swapCandidates(for: session, in: context).map { ($0.date, $0) }
                + coordinator.restDays(forMoving: session, in: context).map { ($0, nil) }).sorted { $0.date < $1.date }
            if !targets.isEmpty {
                Menu("Swap day with") {
                    ForEach(targets, id: \.date) { date, other in
                        if let other {
                            Button("\(Format.weekday.string(from: date)): \(other.title)") { coordinator.swapDays(session, other, in: context) }
                        } else {
                            Button("\(Format.weekday.string(from: date)): Rest") { coordinator.move(session, to: date, in: context) }
                        }
                    }
                }
            }
        } label: {
            Chip(symbol: "arrow.triangle.swap", text: "Change", tint: Palette.accent)
                .contentShape(.capsule)
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0)
        .accessibilityHidden(!isAvailable)
    }
}
