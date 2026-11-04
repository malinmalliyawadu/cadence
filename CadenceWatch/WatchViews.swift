import Charts
import SwiftUI
import TrainingEngine
import WatchKit

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        Group {
            switch workout.phase {
            case .idle: StartView()
            case .starting: StartingView()
            case .running, .paused, .saving: WorkoutView()
            case .ended: SummaryView()
            }
        }
        .background(Palette.canvas)
    }
}

/// The watch's type: words at medium weight, numbers semibold or bold with monospaced digits so a
/// ticking clock never jitters. The load and the countdown are the two numbers read at a glance
/// mid-set, so they are the largest things the watch draws.
private enum WatchType {
    static let load = Font.cadence(size: 56, weight: .bold).monospacedDigit()
    static let countdown = Font.cadence(size: 44, weight: .bold).monospacedDigit()
    static let hero = Font.cadence(size: 40, weight: .semibold).monospacedDigit()
    static let figure = Font.cadence(size: 18, weight: .semibold).monospacedDigit()
    static let display = Font.cadence(size: 22, weight: .medium)
    static let title = Font.cadence(size: 17, weight: .medium)
    static let unit = Font.cadence(size: 17, weight: .semibold)
    static let body = Font.cadence(size: 15, weight: .medium)
    static let caption = Font.cadence(size: 13, weight: .medium)
}

/// The space kept clear along the screen's sides on every page, so nothing runs into the bezel's curve.
private enum WatchMetrics {
    static let gutter: CGFloat = 10
}

// MARK: Before and after

/// Before a workout: the icon's mark, and Start. Logging the first set on the phone starts one;
/// starting here counts the warm-up too.
struct StartView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                OrbitMark(drawsIn: true)
                    .frame(width: 64, height: 64)
                Text("Strength").font(WatchType.display).foregroundStyle(Palette.ink)
                Button {
                    Task { await workout.start() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.cadence(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                Text(workout.message ?? "Starts when you log your first set on your phone. Start here to count your warm-up.")
                    .font(WatchType.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, WatchMetrics.gutter)
        }
    }
}

/// While Health opens the workout: the mark, which the Start screen just drew, and a word.
struct StartingView: View {
    var body: some View {
        VStack(spacing: 12) {
            OrbitMark().frame(width: 76, height: 76)
            Text("Starting").font(WatchType.body).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// After the workout: how long it ran, the heart rate through it with the rests shaded, and the totals.
struct SummaryView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if workout.saved {
                        OrbitMark().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.amber)
                    }
                    Text(workout.saved ? "Saved to Apple Health" : "Not saved")
                        .font(WatchType.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if let message = workout.message {
                    Text(message).font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.duration(workout.duration))
                        .font(WatchType.hero)
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Duration \(Self.duration(workout.duration))")
                    Text(workout.title)
                        .font(WatchType.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                }
                if workout.heartRates.count > 1, let start = workout.startDate {
                    HeartRateChart(readings: workout.heartRates, rests: workout.rests, span: start...(workout.endDate ?? .now))
                        .frame(height: 84)
                        .padding(.top, 2)
                }
                HStack(alignment: .top, spacing: 8) {
                    Tile(symbol: "heart.fill", tint: Palette.rose, value: workout.metrics.averageHeartRate, unit: "avg bpm")
                    Tile(symbol: "flame.fill", tint: Palette.amber, value: workout.metrics.activeKilocalories, unit: "kcal")
                }
                Button { workout.dismissSummary() } label: {
                    Text("Done").font(WatchType.title).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.glass)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WatchMetrics.gutter)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// Heart rate through the session: a rose line climbing through each set and falling away through
/// each rest, the rests in the icon's deep violet. The peak is marked.
struct HeartRateChart: View {
    let readings: [HeartRateReading]
    let rests: [DateInterval]
    let span: ClosedRange<Date>

    var body: some View {
        let values = readings.map(\.beatsPerMinute)
        let low = ((values.min() ?? 60) - 10).rounded(.down)
        let high = ((values.max() ?? 160) + 16).rounded(.up)
        let peak = readings.max { $0.beatsPerMinute < $1.beatsPerMinute }
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(rests, id: \.self) { rest in
                    RectangleMark(xStart: .value("Rest", rest.start), xEnd: .value("Rest", rest.end))
                        .foregroundStyle(Palette.accentDeep.opacity(0.7))
                }
                ForEach(readings, id: \.date) { reading in
                    AreaMark(x: .value("Time", reading.date), yStart: .value("Floor", low), yEnd: .value("bpm", reading.beatsPerMinute))
                        .foregroundStyle(Palette.rose.opacity(0.16))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", reading.date), y: .value("bpm", reading.beatsPerMinute))
                        .foregroundStyle(Palette.rose)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let peak {
                    PointMark(x: .value("Time", peak.date), y: .value("bpm", peak.beatsPerMinute))
                        .symbolSize(28)
                        .foregroundStyle(Palette.ink)
                        .annotation(position: .top, spacing: 2) {
                            Text("\(Int(peak.beatsPerMinute.rounded()))")
                                .font(.cadence(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                        }
                }
            }
            .chartXScale(domain: span)
            .chartYScale(domain: low...high)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            Text("Heart rate, rests shaded")
                .font(.cadence(size: 11, weight: .medium))
                .foregroundStyle(Palette.inkTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate chart")
        .accessibilityValue(peak.map { "Peak \(Int($0.beatsPerMinute.rounded())) beats per minute" } ?? "")
    }
}

/// A total on a flat card: its glyph, the number, the unit under it.
struct Tile: View {
    let symbol: String
    let tint: Color
    let value: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–").font(WatchType.figure).foregroundStyle(Palette.ink)
            Text(unit).font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
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
/// to do now: during rest the ring counting down, otherwise the set to lift.
struct LiveView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let resting = workout.rest.map { !$0.timer.isOver(at: context.date) } ?? false
            VStack(alignment: .leading, spacing: 0) {
                StatusLine(elapsed: workout.elapsed(at: context.date), metrics: workout.metrics)
                Group {
                    if workout.phase == .paused {
                        PausedBlock()
                    } else if resting, let rest = workout.rest {
                        RestBlock(rest: rest, now: context.date)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else {
                        SetBlock(set: workout.rest?.set ?? workout.next, restOver: workout.rest, now: context.date, title: workout.title)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .padding(.horizontal, WatchMetrics.gutter)
            .animation(Motion.reveal, value: resting)
        }
    }
}

/// Time since the start, then heart rate and energy, their glyphs standing in for the units. The heart
/// gives a beat each time a new reading lands.
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
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func reading(symbol: String, tint: Color, value: Double?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: value)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–").foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(Int($0.rounded())) \(unit)" } ?? "No \(unit) yet")
    }
}

/// The set to lift, sat low on the screen where the eye lands between reps: the movement, a pip for
/// each set with this one lit, and the load and reps as large as the watch can draw them.
struct SetBlock: View {
    let set: LiveSet?
    /// A rest that has run out, so the screen says how long ago.
    let restOver: RestDisplay?
    let now: Date
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let restOver {
                Text("Rest over, +\(SummaryView.duration(restOver.timer.overtime(at: now).rounded(.down)))")
                    .font(WatchType.caption.monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }
            if let set {
                Text(set.movement)
                    .font(WatchType.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 8) {
                    if let number = set.number, let count = set.count {
                        SetPips(number: number, count: count)
                    }
                    Text(set.setLabel).font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
                }
                LoadText(set: set)
                    .padding(.top, -2)
            } else {
                Text(title).font(WatchType.title).foregroundStyle(Palette.ink)
                Text("Log sets on your phone. The next one shows here.")
                    .font(WatchType.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A pip for each set of the movement: the ones done in a quieter violet, this one long and lit, the rest to come dark.
struct SetPips: View {
    let number: Int
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max(1, min(count, 10)), id: \.self) { index in
                Capsule()
                    .fill(index == number ? Palette.accent : index < number ? Palette.accent.opacity(0.4) : Palette.raised)
                    .frame(width: index == number ? 16 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "60 kg × 8" with the numbers large and the unit and times sign small, one line that shrinks as a
/// whole for a long load. Bodyweight with nothing added is the reps alone. A message without the parts
/// falls back to the phone's label.
struct LoadText: View {
    let set: LiveSet

    var body: some View {
        Group {
            if let kg = set.weightKg, let reps = set.reps {
                let count = Text("\(reps)").font(WatchType.load).foregroundStyle(Palette.ink)
                if kg > 0 {
                    let load = Text(Format.kg(kg)).font(WatchType.load).foregroundStyle(Palette.ink)
                    let unit = Text(" kg ").font(WatchType.unit).foregroundStyle(Palette.inkSecondary)
                    let times = Text("× ").font(WatchType.unit).foregroundStyle(Palette.inkTertiary)
                    Text("\(load)\(unit)\(times)\(count)")
                } else {
                    let unit = Text(" reps").font(WatchType.unit).foregroundStyle(Palette.inkSecondary)
                    Text("\(count)\(unit)")
                }
            } else {
                Text(set.target).font(.cadence(size: 34, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.ink)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityLabel(set.target)
    }
}

/// The rest as the app's ring, without its dial: the violet arc running back to twelve with the mint dot at its head,
/// the countdown in the middle over the set it leads to. +30 s and Skip sit in the corners the ring
/// leaves free, where the Workout app keeps its controls.
struct RestBlock: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let rest: RestDisplay
    let now: Date

    var body: some View {
        let remaining = rest.timer.remaining(at: now)
        ProgressRing(progress: 1 - rest.timer.progress(at: now), lineWidth: 11, showsDial: false) {
            VStack(spacing: 0) {
                Text("Rest").font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
                Text(Format.countdown(remaining))
                    .font(WatchType.countdown)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.settle, value: Int(remaining.rounded(.up)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(rest.target)
                    .font(WatchType.caption.monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest, \(Format.countdown(remaining)) left. Next, \(rest.movement), \(rest.setLabel.lowercased()), \(rest.target)")
        }
        .opacity(isLuminanceReduced ? 0.6 : 1)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            Button { workout.addRest() } label: {
                Text("+30")
                    .font(.cadence(size: 12, weight: .semibold).monospacedDigit())
                    .fixedSize()
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.mini)
            .fixedSize()
            .accessibilityLabel("Add 30 seconds")
        }
        .overlay(alignment: .bottomTrailing) {
            Button { workout.skipRest() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.mini)
            .fixedSize()
            .accessibilityLabel("Skip rest")
        }
    }
}

struct PausedBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Paused").font(.cadence(size: 34, weight: .medium)).foregroundStyle(Palette.ink)
            Text("Swipe right to resume").font(WatchType.caption).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.bottom, 4)
    }
}

/// End and pause as large Liquid Glass circles with their names under them, under the time so far.
/// Either one returns to the workout page.
struct ControlsView: View {
    @Environment(WorkoutManager.self) private var workout
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(SummaryView.duration(workout.elapsed(at: context.date)))
                    .font(WatchType.figure)
                    .foregroundStyle(workout.phase == .paused ? Palette.accent : Palette.inkSecondary)
            }
            HStack(alignment: .top, spacing: 14) {
                control(symbol: "xmark", title: "End", tint: Palette.rose) {
                    workout.end(saving: true)
                }
                if workout.phase == .paused {
                    control(symbol: "play.fill", title: "Resume", tint: Palette.accent, prominent: true) {
                        workout.resume()
                        onAction()
                    }
                } else {
                    control(symbol: "pause.fill", title: "Pause", tint: Palette.accent) {
                        workout.pause()
                        onAction()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(workout.phase == .saving)
    }

    /// Clear glass with the glyph in its colour; prominent is the one violet action, filled.
    private func control(symbol: String, title: String, tint: Color, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Group {
                if prominent {
                    Button(action: action) { glyph(symbol).foregroundStyle(Palette.onAccent) }
                        .buttonStyle(.glassProminent)
                } else {
                    Button(action: action) { glyph(symbol).foregroundStyle(tint) }
                        .buttonStyle(.glass)
                }
            }
            .buttonBorderShape(.circle)
            .fixedSize()
            .tint(tint)
            .accessibilityLabel(title)
            Text(title).font(WatchType.caption).foregroundStyle(Palette.ink)
                .accessibilityHidden(true)
        }
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 50, height: 50)
    }
}
