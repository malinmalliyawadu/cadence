import SwiftUI
import TrainingEngine

/// The rest between sets, pinned under the session while it runs: the countdown in violet, the set
/// it leads to, and buttons to take or add half a minute or skip it. When it runs out it says
/// "Rest over" in violet and counts the time since, until the next set is logged. It floats over
/// the sets, so it is glass, and its controls are outlined rather than glass on glass.
struct RestCard: View {
    let state: RestActivityAttributes.ContentState
    let onAdjust: (Double) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: state.timer.startedAt, by: 1)) { context in
            let timer = state.timer
            let isOver = timer.isOver(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isOver ? "Rest over" : "Rest")
                            .font(.label)
                            .foregroundStyle(isOver ? Palette.accent : Palette.inkSecondary)
                        Text(isOver ? "+\(Format.countdown(timer.overtime(at: context.date)))" : Format.countdown(timer.remaining(at: context.date)))
                            .font(.system(size: 34, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isOver ? Palette.ink : Palette.accent)
                            .contentTransition(.numericText(countsDown: !isOver))
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 4)
                    Button { onAdjust(-RestTimerStep.seconds) } label: {
                        Chip(text: "−\(Int(RestTimerStep.seconds)) s", tint: Palette.inkSecondary)
                    }
                    .buttonStyle(.control)
                    .disabled(isOver)
                    .opacity(isOver ? 0.4 : 1)
                    .accessibilityLabel("Take \(Int(RestTimerStep.seconds)) seconds off the rest")
                    Button { onAdjust(RestTimerStep.seconds) } label: {
                        Chip(text: "+\(Int(RestTimerStep.seconds)) s", tint: Palette.inkSecondary)
                    }
                    .buttonStyle(.control)
                    .accessibilityLabel("Add \(Int(RestTimerStep.seconds)) seconds of rest")
                    Button(action: onSkip) {
                        Image(systemName: isOver ? "xmark" : "forward.end")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 40, height: 40)
                            .overlay { Circle().strokeBorder(Palette.stroke, lineWidth: 1) }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.control)
                    .accessibilityLabel(isOver ? "Dismiss the rest" : "Skip the rest")
                }
                // The fill runs with the clock, a second at a time.
                ProgressBar(value: timer.progress(at: context.date), animation: .linear(duration: 1))
                Text("Next: \(state.movement), \(state.setLabel.lowercased()) at \(state.target)")
                    .font(.body2)
                    .foregroundStyle(isOver ? Palette.ink : Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(16)
            .glassEffect(.regular.tint(Palette.accentDeep.opacity(0.4)), in: .rect(cornerRadius: 24, style: .continuous))
            // Running out turns the countdown white and the label violet, as a change rather than a cut.
            .animation(Motion.settle, value: isOver)
        }
    }
}
