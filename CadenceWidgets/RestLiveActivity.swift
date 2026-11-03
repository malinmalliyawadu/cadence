import ActivityKit
import AppIntents
import SwiftUI
import TrainingEngine
import WidgetKit

/// The rest between sets on the Lock Screen and in the Dynamic Island: the countdown in violet,
/// what comes next, and buttons to add rest or skip it. Once the rest runs out the activity goes
/// stale and says so, counting the time since.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(state: context.state, isOver: context.isStale)
                .activityBackgroundTint(Palette.surface)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            let state = context.state
            let isOver = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        RestTitle(isOver: isOver)
                        RestCountdown(timer: state.timer, isOver: isOver, size: 34)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next").font(.label).foregroundStyle(Palette.inkSecondary)
                        Text(state.setLabel).font(.rowTitle).foregroundStyle(Palette.ink)
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(state.movement) at \(state.target)")
                            .font(.body2)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                        RestButtons()
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                RestRing(timer: state.timer, isOver: isOver)
                    .padding(.leading, 2)
            } compactTrailing: {
                RestCountdown(timer: state.timer, isOver: isOver, size: 15)
                    .frame(maxWidth: 46)
            } minimal: {
                RestRing(timer: state.timer, isOver: isOver)
            }
            .keylineTint(Palette.accent)
        }
    }
}

struct RestLockScreenView: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    RestTitle(isOver: isOver)
                    RestCountdown(timer: state.timer, isOver: isOver, size: 40)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(state.movement).font(.rowTitle).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("\(state.setLabel) at \(state.target)").font(.body2).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                .padding(.top, 2)
            }
            if !isOver {
                ProgressView(timerInterval: state.timer.startedAt...state.timer.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Palette.accent)
            }
            RestButtons()
        }
        .padding(16)
    }
}

/// "Rest", or "Rest over" in violet once it has run out.
private struct RestTitle: View {
    let isOver: Bool

    var body: some View {
        Text(isOver ? "Rest over" : "Rest")
            .font(.label)
            .foregroundStyle(isOver ? Palette.accent : Palette.inkSecondary)
    }
}

/// Counts down to the end of the rest, then up from it with a plus.
private struct RestCountdown: View {
    let timer: RestTimer
    let isOver: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if isOver {
                Text("+\(timer.endsAt, style: .timer)")
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                    .foregroundStyle(Palette.accent)
            }
        }
        .font(.cadence(size: size, weight: .semibold).monospacedDigit())
        .multilineTextAlignment(size < 20 ? .trailing : .leading)
        .contentTransition(.numericText(countsDown: true))
    }
}

/// The rest as a ring that empties, for the compact and minimal Dynamic Island.
private struct RestRing: View {
    let timer: RestTimer
    let isOver: Bool

    var body: some View {
        if isOver {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Palette.accent, lineWidth: 2.5) }
        } else {
            ProgressView(timerInterval: timer.startedAt...timer.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(Palette.accent)
            .frame(width: 22, height: 22)
        }
    }
}

private struct RestButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AddRestIntent()) { label("\(Int(RestTimerStep.seconds)) s", symbol: "plus") }
            Button(intent: SkipRestIntent()) { label("Skip", symbol: "forward.end") }
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.cadence(size: 15, weight: .medium))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Palette.raised, in: .capsule)
    }
}
