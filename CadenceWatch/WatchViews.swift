import SwiftUI
import TrainingEngine
import WatchKit

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        Group {
            switch workout.phase {
            case .idle: StartView()
            case .starting: ProgressView()
            case .running, .paused, .saving: WorkoutView()
            case .ended: SummaryView()
            }
        }
        .background(Palette.canvas)
    }
}

/// The watch's type: words at medium weight, numbers semibold with monospaced digits so a ticking clock never jitters.
private enum WatchType {
    static let hero = Font.system(size: 40, weight: .semibold).monospacedDigit()
    static let figure = Font.system(size: 18, weight: .semibold).monospacedDigit()
    static let title = Font.system(size: 17, weight: .medium)
    static let body = Font.system(size: 15, weight: .medium)
    static let caption = Font.system(size: 13, weight: .medium)
}

// MARK: Before and after

/// Before a workout. Logging the first set on the phone starts one; starting here counts the warm-up too.
struct StartView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strength").font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.ink)
                    Text(workout.message ?? "Starts when you log your first set on your phone. Start here to count your warm-up.")
                        .font(WatchType.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task { await workout.start() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(WatchType.title)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CapsuleButtonStyle(fill: Palette.accent, ink: .white))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SummaryView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: workout.saved ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(workout.saved ? Palette.sage : Palette.amber)
                    Text(workout.saved ? "Saved to Apple Health" : "Not saved")
                        .font(WatchType.body)
                        .foregroundStyle(Palette.ink)
                }
                if let message = workout.message {
                    Text(message).font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
                }
                Text(Self.duration(workout.duration))
                    .font(WatchType.hero)
                    .foregroundStyle(Palette.ink)
                    .accessibilityLabel("Duration \(Self.duration(workout.duration))")
                HStack(spacing: 16) {
                    Figure(symbol: "heart.fill", tint: Palette.rose, value: workout.metrics.averageHeartRate, unit: "avg bpm")
                    Figure(symbol: "flame.fill", tint: Palette.amber, value: workout.metrics.activeKilocalories, unit: "kcal")
                }
                Button { workout.dismissSummary() } label: {
                    Text("Done").font(WatchType.title).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CapsuleButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

// MARK: The workout

/// Three pages, as in the Workout app: controls to the left, the workout in the middle, what's playing to the right.
struct WorkoutView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var page = Page.workout

    enum Page { case controls, workout, media }

    var body: some View {
        TabView(selection: $page) {
            ControlsView(onAction: { page = .workout }).tag(Page.controls)
            LiveView().tag(Page.workout)
            NowPlayingView().tag(Page.media)
        }
        .tabViewStyle(.page)
    }
}

/// The middle page. A status line along the top (time since the start, heart rate, energy); under it, what
/// to do now: during rest the countdown leads, otherwise the set to lift.
struct LiveView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let resting = workout.rest.map { !$0.timer.isOver(at: context.date) } ?? false
            VStack(alignment: .leading, spacing: 0) {
                StatusLine(elapsed: workout.elapsed(at: context.date), metrics: workout.metrics)
                    .padding(.bottom, 6)
                Group {
                    if workout.phase == .paused {
                        PausedBlock()
                    } else if resting, let rest = workout.rest {
                        RestBlock(rest: rest, now: context.date)
                    } else {
                        SetBlock(set: workout.rest?.set ?? workout.next, restOver: workout.rest, now: context.date, title: workout.title)
                    }
                }
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.snappy(duration: 0.25), value: resting)
        }
    }
}

/// Time since the start, then heart rate and energy, their glyphs standing in for the units.
struct StatusLine: View {
    let elapsed: TimeInterval
    let metrics: LiveMetrics

    var body: some View {
        HStack(spacing: 10) {
            Text(SummaryView.duration(elapsed))
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("Elapsed \(SummaryView.duration(elapsed))")
            Spacer(minLength: 0)
            reading(symbol: "heart.fill", tint: Palette.rose, value: metrics.heartRate, unit: "beats per minute")
            reading(symbol: "flame.fill", tint: Palette.amber, value: metrics.activeKilocalories, unit: "kilocalories")
        }
        .font(WatchType.figure)
    }

    private func reading(symbol: String, tint: Color, value: Double?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–").foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(Int($0.rounded())) \(unit)" } ?? "No \(unit) yet")
    }
}

/// The set to lift: the load and reps as the hero, the movement and which set above them.
struct SetBlock: View {
    let set: LiveSet?
    /// A rest that has run out, so the screen says how long ago.
    let restOver: RestDisplay?
    let now: Date
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let restOver {
                Text("Rest over, +\(SummaryView.duration(restOver.timer.overtime(at: now).rounded(.down)))")
                    .font(WatchType.caption.monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .padding(.bottom, 2)
            }
            if let set {
                Text(set.movement)
                    .font(WatchType.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(set.setLabel).font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
                Text(set.target)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
            } else {
                Text(title).font(WatchType.title).foregroundStyle(Palette.ink)
                Text("Log sets on your phone. The next one shows here.")
                    .font(WatchType.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The rest counting down, in blue as the thing happening now, with a bar that empties as it runs and
/// the same +30 s and Skip as the phone.
struct RestBlock: View {
    @Environment(WorkoutManager.self) private var workout
    let rest: RestDisplay
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rest").font(WatchType.body).foregroundStyle(Palette.inkSecondary)
                Spacer()
                Text(Format.countdown(rest.timer.remaining(at: now)))
                    .font(WatchType.hero)
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.numericText(countsDown: true))
            }
            Capsule()
                .fill(Palette.raised)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Palette.accent)
                            .frame(width: proxy.size.width * (1 - rest.timer.progress(at: now)))
                    }
                }
                .accessibilityHidden(true)
            Text("\(rest.movement), \(rest.setLabel.lowercased())")
                .font(WatchType.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 8) {
                Button { workout.addRest() } label: { Text("+30 s").frame(maxWidth: .infinity, minHeight: 40) }
                Button { workout.skipRest() } label: { Text("Skip").frame(maxWidth: .infinity, minHeight: 40) }
            }
            .font(WatchType.body)
            .buttonStyle(CapsuleButtonStyle())
        }
        .accessibilityElement(children: .contain)
    }
}

struct PausedBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Paused").font(.system(size: 34, weight: .medium)).foregroundStyle(Palette.ink)
            Text("Swipe right to resume").font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
        }
    }
}

/// A flat capsule the full width it is given, which the system's bordered buttons on watchOS are not.
/// Pressing dims and shrinks it a touch.
struct CapsuleButtonStyle: ButtonStyle {
    var fill: Color = Palette.raised
    var ink: Color = Palette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ink)
            .background(fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

/// A reading with its glyph and unit, a dash until the watch has one.
struct Figure: View {
    let symbol: String
    let tint: Color
    let value: Double?
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–").font(WatchType.figure).foregroundStyle(Palette.ink)
            Text(unit).font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// End and pause, as round buttons with their names under them. Either one returns to the workout page.
struct ControlsView: View {
    @Environment(WorkoutManager.self) private var workout
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            control(symbol: "xmark", title: "End", tint: Palette.rose) {
                workout.end(saving: true)
            }
            if workout.phase == .paused {
                control(symbol: "arrow.clockwise", title: "Resume", tint: Palette.accent) {
                    workout.resume()
                    onAction()
                }
            } else {
                control(symbol: "pause", title: "Pause", tint: Palette.accent) {
                    workout.pause()
                    onAction()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(workout.phase == .saving)
    }

    private func control(symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 64, height: 52)
            }
            .buttonStyle(.bordered)
            .tint(tint)
            .accessibilityLabel(title)
            Text(title).font(WatchType.caption).foregroundStyle(Palette.ink)
                .accessibilityHidden(true)
        }
    }
}
