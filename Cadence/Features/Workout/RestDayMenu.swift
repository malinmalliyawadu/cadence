import SwiftData
import SwiftUI
import TrainingEngine

/// What the athlete can do with a rest day from today on: train instead, with a lift, a run or a
/// class, or bring over a session planned for another day this week.
struct RestDayMenu: View {
    let date: Date
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    private var isAvailable: Bool { date >= coordinator.calendar.startOfDay(for: .now) }

    var body: some View {
        if isAvailable {
            Menu {
                Section("Train instead") {
                    ForEach(BodyHalf.allCases, id: \.self) { half in
                        Menu("\(half.displayName) body") {
                            ForEach(FocusArea.areas(for: half)) { focus in
                                Button("\(focus.displayName) focus") { coordinator.addStrength(on: date, half: half, focus: focus, in: context) }
                            }
                        }
                    }
                    Menu("Run") {
                        ForEach(RunKind.allCases, id: \.self) { kind in
                            Button(kind.displayName) { coordinator.addRun(on: date, kind: kind, in: context) }
                        }
                    }
                    Button("Hot yoga") { coordinator.addYoga(on: date, in: context) }
                }
                let candidates = coordinator.moveCandidates(to: date, in: context)
                if !candidates.isEmpty {
                    Menu("Move here") {
                        ForEach(candidates) { session in
                            Button("\(Format.weekday.string(from: session.date)): \(session.title)") {
                                coordinator.move(session, to: date, in: context)
                            }
                        }
                    }
                }
            } label: {
                Chip(symbol: "arrow.triangle.swap", text: "Change", tint: Palette.accent, glass: true)
                    .contentShape(.capsule)
            }
        }
    }
}
