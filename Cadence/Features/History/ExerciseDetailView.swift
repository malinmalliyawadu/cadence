import Charts
import SwiftData
import SwiftUI
import TrainingEngine

/// The movement screen on its own, for checking a movement from inside a session.
struct ExerciseDetailSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exercise: exercise, opensSessions: false)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationBackground(Palette.canvas)
    }
}

/// One movement's story: how it moves, then its trend (estimated max, heaviest set or volume over
/// time), the bests, what comes next, and every session it was logged in.
struct ExerciseDetailView: View {
    let exercise: Exercise
    /// Whether a logged session opens. Off in the sheet over a session, which has nowhere to push it.
    var opensSessions = true
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TrainingSession> { $0.statusRaw == "completed" }, sort: \TrainingSession.date)
    private var sessions: [TrainingSession]
    @Query private var profiles: [AthleteProfile]
    /// Worked out in the background when the finished sessions change, as on History. Nil until the first pass.
    @State private var history: MovementHistory?

    private var bodyweight: Double { profiles.first?.bodyweightKg ?? 0 }

    var body: some View {
        let movement = history?.movements.first
        let points = movement?.points ?? []
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        DisplayText(text: exercise.name)
                        Text("\(exercise.primary.displayName) \(exercise.role.rawValue), \(exercise.equipment.rawValue). Loads move in \(Format.kg(exercise.equipment.incrementKg))\u{00A0}kg steps.")
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    Card { MovementVisual(exercise: exercise) }

                    if points.count >= 2 { ExerciseTrendCard(exercise: exercise, points: points) }
                    if !points.isEmpty { BestsCard(records: ExerciseTrend.records(of: points)) }
                    if history != nil { nextTime(history: movement?.entries ?? []) }

                    if let movement {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Sessions")
                            LazyVStack(spacing: 8) {
                                let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                                // By position: a movement done twice in a session gives two points on one date.
                                ForEach(movement.points.indices.reversed(), id: \.self) { index in
                                    sessionRow(movement.points[index], sets: movement.entries[index].workingSets, session: byID[movement.sessionIDs[index]])
                                }
                            }
                        }
                    } else if history != nil {
                        Text("No sessions logged on this movement yet.").font(.body2).foregroundStyle(Palette.inkTertiary)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(exercise.primary.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: MovementHistory.Inputs(sessions: sessions.map(\.id), bodyweightKg: bodyweight)) {
            history = await HistoryReader.history(in: context, bodyweightKg: bodyweight, exerciseID: exercise.id)
        }
    }

    private func nextTime(history: [ExerciseHistoryEntry]) -> some View {
        let next = Progression.nextLoad(for: exercise, history: history, repRange: WorkoutGenerator.openerScheme.reps,
                                        targetRIR: WorkoutGenerator.openerScheme.rir, bodyweightKg: bodyweight)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    TitleIcon(symbol: "arrow.up.right", tint: Palette.accent)
                    Text("Next time").font(.rowTitle).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(Format.weight(next.weightKg)).font(.numeral).foregroundStyle(Palette.ink)
                }
                Text(next.rationale).font(.body2).foregroundStyle(Palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ point: ExerciseTrendPoint, sets: [PerformedSet], session: TrainingSession?) -> some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.monthDay.string(from: point.date)).font(.label).foregroundStyle(Palette.inkSecondary)
                .frame(width: 52, alignment: .leading)
            Text(sets.map { "\(Format.kg($0.weightKg))×\($0.reps)" }.joined(separator: "  "))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if point.isBest {
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Palette.amber)
                    .accessibilityLabel("Best estimated max")
            }
            Text("\(Format.estimate(point.oneRepMax)) kg").font(.label.monospacedDigit()).foregroundStyle(Palette.inkTertiary)
            if opensSessions, session != nil {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 14)
        .accessibilityElement(children: .combine)

        if opensSessions, let session {
            NavigationLink(value: session) { row }
                .buttonStyle(.pressable)
                .sessionZoomSource(session, cornerRadius: 14)
        } else {
            row
        }
    }
}

// MARK: Trend

/// The movement's trend over a window: the latest value and how far it has come, the chart, and
/// the window. Dragging across the chart reads off any session.
private struct ExerciseTrendCard: View {
    let exercise: Exercise
    let points: [ExerciseTrendPoint]
    @State private var metric: TrendMetric = .oneRepMax
    /// Nil until picked: the longest window that is not the whole history, or all of it when short.
    @State private var range: TrendRange?
    @State private var selectedDate: Date?

    private var effectiveRange: TrendRange {
        if let range { return range }
        let sixMonths = TrendRange.sixMonths.start(from: .now) ?? .distantPast
        return points.filter { $0.date >= sixMonths }.count >= 2 ? .sixMonths : .all
    }
    private var shown: [ExerciseTrendPoint] {
        guard let start = effectiveRange.start(from: .now) else { return points }
        return points.filter { $0.date >= start }
    }
    private var selected: ExerciseTrendPoint? {
        guard let selectedDate else { return nil }
        return shown.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        let shown = shown
        let summary = ExerciseTrend.summary(of: shown, metric: metric)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Trend") {
                MenuChip(title: "Measure", selection: $metric, options: TrendMetric.allCases.map { ($0, $0.displayName) })
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    readout(summary: summary)
                    if shown.count >= 2 {
                        chart(shown)
                    } else {
                        Text("Fewer than two sessions in this window. Pick a longer one to see the trend.")
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                    ChipPicker(title: "Window", selection: Binding(get: { effectiveRange }, set: { range = $0; selectedDate = nil }),
                               options: TrendRange.allCases.map { ($0, $0.label) })
                }
            }
        }
    }

    /// The number: the session under the finger, else the latest with its change over the window.
    private func readout(summary: ExerciseTrendSummary?) -> some View {
        let point = selected ?? shown.last ?? points.last
        return VStack(alignment: .leading, spacing: 6) {
            Text(caption(for: point)).font(.label).foregroundStyle(Palette.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let point {
                    Text(metric == .topSet ? Format.set(point.topSet) : Format.value(point.value(of: metric), metric: metric))
                        .font(.numeral).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if selected == nil, let summary, let direction = summary.direction {
                    StatusChip(text: direction.displayName, tint: Optional(direction).tint)
                }
            }
            if selected == nil, let summary {
                HStack(spacing: 4) {
                    TrendChange(summary: summary, metric: metric)
                    Text(sinceText(summary)).font(.label).foregroundStyle(Palette.inkTertiary)
                }
            } else if let point, metric != .topSet {
                Text("\(Format.set(point.topSet)) top set, \(point.workingSets) working sets")
                    .font(.label.monospacedDigit()).foregroundStyle(Palette.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(for point: ExerciseTrendPoint?) -> String {
        guard let point else { return metric.displayName }
        let day = Format.monthDay.string(from: point.date)
        return selected == nil ? "\(metric.displayName), last on \(day)" : "\(metric.displayName) on \(day)"
    }

    /// "(8%) since 3 Aug": the change's sign is on the kilograms beside it.
    private func sinceText(_ summary: ExerciseTrendSummary) -> String {
        let since = "since \(Format.monthDay.string(from: summary.first.date))"
        guard abs(summary.changeFraction) >= 0.005 else { return since }
        return "(\(Format.percent(abs(summary.changeFraction)))) \(since)"
    }

    private func chart(_ shown: [ExerciseTrendPoint]) -> some View {
        Chart {
            ForEach(shown, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Floor", floor(shown)), yEnd: .value(metric.displayName, point.value(of: metric)))
                    .foregroundStyle(Palette.accent.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value(metric.displayName, point.value(of: metric)))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(.init(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                if shown.count <= 40 || point.date == selected?.date {
                    PointMark(x: .value("Date", point.date), y: .value(metric.displayName, point.value(of: metric)))
                        .foregroundStyle(point.isBest && metric == .oneRepMax ? Palette.amber : Palette.accent)
                        .symbolSize(point.date == selected?.date ? 110 : 36)
                }
            }
            if let selected {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineStyle(.init(lineWidth: 1))
            }
        }
        .chartYScale(domain: floor(shown)...ceiling(shown))
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Palette.inkTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(height: 200)
        .sensoryFeedback(.selection, trigger: selected?.date)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.displayName) over \(shown.count) sessions")
        .accessibilityValue(shown.last.map { "Latest \(Format.value($0.value(of: metric), metric: metric))" } ?? "")
    }

    /// The chart sits on the window's own range with a little room either side, so small changes read.
    private func floor(_ shown: [ExerciseTrendPoint]) -> Double {
        let values = shown.map { $0.value(of: metric) }
        let low = values.min() ?? 0, high = values.max() ?? 0
        return max(0, low - max((high - low) * 0.2, high * 0.03, 1))
    }

    private func ceiling(_ shown: [ExerciseTrendPoint]) -> Double {
        let values = shown.map { $0.value(of: metric) }
        let low = values.min() ?? 0, high = values.max() ?? 0
        return high + max((high - low) * 0.15, high * 0.02, 1)
    }
}

private enum TrendRange: CaseIterable, Hashable {
    case threeMonths, sixMonths, year, all

    var label: String {
        switch self {
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .year: "1Y"
        case .all: "All"
        }
    }

    func start(from now: Date) -> Date? {
        switch self {
        case .threeMonths: Calendar.current.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: Calendar.current.date(byAdding: .month, value: -6, to: now)
        case .year: Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

extension TrendMetric {
    var displayName: String {
        switch self {
        case .oneRepMax: "Estimated max"
        case .topSet: "Heaviest set"
        case .volume: "Volume"
        }
    }
}

// MARK: Bests

/// The sessions that set each record, so a best can be found again.
private struct BestsCard: View {
    let records: ExerciseRecords

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TitleIcon(symbol: "star", tint: Palette.amber)
                    Text("Bests").font(.rowTitle).foregroundStyle(Palette.ink)
                }
                VStack(spacing: 10) {
                    if let point = records.bestOneRepMax { row("Estimated max", Format.value(point.oneRepMax, metric: .oneRepMax), point.date) }
                    if let point = records.heaviestSet { row("Heaviest set", Format.set(point.topSet), point.date) }
                    if let point = records.mostVolume { row("Most volume", Format.value(point.volumeKg, metric: .volume), point.date) }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.body2).foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: 8)
            Text(value).font(.numeralSmall).foregroundStyle(Palette.ink)
            Text(Format.monthDay.string(from: date)).font(.label.monospacedDigit()).foregroundStyle(Palette.inkTertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
