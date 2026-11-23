import Charts
import SwiftUI
import TrainingEngine

/// A Home figure that slides up an explainer when tapped.
enum Explainer: String, Identifiable {
    case trainingLoad, monotony, strain, recovery, race
    var id: String { rawValue }

    var title: String {
        switch self {
        case .trainingLoad: "Training load"
        case .monotony: "Monotony"
        case .strain: "Strain"
        case .recovery: "Recovery"
        case .race: "Race times"
        }
    }
}

/// What a figure on Home is, drawn from the athlete's own data: the number and its verdict, a
/// chart of what is behind it, the sum with today's values, and what the planner does with it.
/// Half height shows the number and its chart; pull up for the rest. The title stays put.
struct ExplainerSheet: View {
    let explainer: Explainer
    let snapshot: LoadSnapshot
    var recovery: RecoveryStatus?
    var lifting: RecoveryStatus.TodaysLifting = .none
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }

    private var titleBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(explainer.title).font(.title2).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Button { dismiss() } label: { GlassIcon(symbol: "xmark", size: 40) }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch explainer {
                case .trainingLoad: TrainingLoadExplainer(snapshot: snapshot)
                case .monotony: MonotonyExplainer(snapshot: snapshot)
                case .strain: StrainExplainer(snapshot: snapshot)
                case .recovery:
                    if let recovery { RecoveryExplainer(recovery: recovery, lifting: lifting) }
                case .race: RaceExplainer()
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }
}

// MARK: Training load

private struct TrainingLoadExplainer: View {
    let snapshot: LoadSnapshot

    private static let zones: [(LoadZone, String)] = [
        (.undertrained, "Under 0.8"), (.optimal, "0.8 to 1.3"), (.elevated, "1.3 to 1.5"), (.danger, "Over 1.5"),
    ]
    private static let range = 0.4...1.8

    private var ratios: [(date: Date, acwr: Double)] {
        snapshot.series.suffix(42).compactMap { day in day.acwr.map { (day.date, $0) } }
    }

    var body: some View {
        let zone = snapshot.zone
        ExplainerHeader(value: Format.ratio(snapshot.acwr), verdict: zone.displayName,
                        tint: zone.tint, headline: Readiness.from(snapshot).headline)
        if ratios.count >= 2 {
            ChartCard(title: "Six weeks of the ratio") { chart }
        } else {
            ChartCard(title: "Six weeks of the ratio") {
                Text("The ratio shows once your chronic load passes 20 a day, a few weeks into logging. Until then there is no base to compare a week with.")
                    .font(.body2).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let today = snapshot.today, let acwr = snapshot.acwr {
            Worked(caption: "Both are averages of daily load, so a rest day counts as a zero.") {
                Equation(left: .init(label: "Acute, 7 day", value: Format.load(today.acute)), symbol: "÷",
                         right: .init(label: "Chronic, 28 day", value: Format.load(today.chronic)),
                         result: .init(label: "Ratio", value: Format.ratio(acwr)))
            }
        }
        ExplainerSection(title: "What it is", text: "Acute is roughly your last week of training, chronic your last month: the base you are fit for. The ratio says whether this week is building on that base or getting ahead of it. Below 0.8 you are doing less than you can handle; above 1.5 the week has outrun what your body is used to, which is when injuries and illness tend to arrive.")
        ExplainerSection(title: "How load is counted", text: "Every session becomes one number: how hard it felt, 1 to 10, times its minutes. Lifting, running and yoga share the scale, so a long run can be weighed against a leg day. Both averages weight recent days more, over 7 and 28 days, so a big session fades out gradually rather than dropping off a cliff a week later. Until something is logged today the ratio is read as of yesterday, so a morning does not look like a rest day.")
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "What Cadence does in each zone")
            VStack(spacing: 4) {
                ForEach(Self.zones, id: \.0) { zone, range in
                    LevelRow(name: zone.displayName, detail: range, effect: effect(of: zone),
                             tint: zone.tint, isCurrent: zone == snapshot.zone)
                }
            }
        }
    }

    private var chart: some View {
        let first = ratios.first?.date ?? .now, last = ratios.last?.date ?? .now
        return Chart {
            ForEach(Self.zones, id: \.0) { zone, _ in
                let band = Self.band(zone)
                RectangleMark(xStart: .value("Start", first), xEnd: .value("End", last),
                              yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                    .foregroundStyle(zone.tint.opacity(zone == snapshot.zone ? 0.16 : 0.07))
            }
            ForEach(ratios, id: \.date) { point in
                LineMark(x: .value("Day", point.date), y: .value("Ratio", clamped(point.acwr)))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(.init(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
            if let point = ratios.last {
                PointMark(x: .value("Day", point.date), y: .value("Ratio", clamped(point.acwr)))
                    .foregroundStyle(snapshot.zone.tint)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: Self.range)
        .chartXScale(domain: first...last)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.8, 1.3, 1.5]) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .chartXAxis { weekAxis }
        .frame(height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Acute to chronic ratio over the last six weeks, against its zones")
        .accessibilityValue("Today \(Format.ratio(snapshot.acwr)), \(snapshot.zone.displayName)")
    }

    private func clamped(_ value: Double) -> Double { min(max(value, Self.range.lowerBound), Self.range.upperBound) }

    private static func band(_ zone: LoadZone) -> ClosedRange<Double> {
        switch zone {
        case .undertrained: range.lowerBound...0.8
        case .optimal: 0.8...1.3
        case .elevated: 1.3...1.5
        case .danger, .building: 1.5...range.upperBound
        }
    }

    private func effect(of zone: LoadZone) -> String {
        let readiness = Readiness.from(zone: zone)
        var parts = ["Week planned at \(Format.percent(readiness.weeklyLoadFactor)) of your base"]
        if readiness.loadMultiplier < 1 { parts.append("lifts \(Format.percent(1 - readiness.loadMultiplier)) lighter") }
        if readiness.setReduction > 0 { parts.append("a set fewer on compounds and accessories") }
        return parts.joined(separator: ", ")
    }
}

// MARK: Monotony

private struct MonotonyExplainer: View {
    let snapshot: LoadSnapshot
    @Environment(PlanCoordinator.self) private var coordinator

    private var days: [DailyLoad] { Array(snapshot.series.suffix(7)) }
    private var week: WeeklyLoad? { snapshot.weekly.last }
    private var trend: [WeeklyLoad] { snapshot.weekly.suffix(42).filter { $0.monotony != nil } }
    private var isFlat: Bool { (snapshot.monotony ?? 0) > LoadAnalysis.monotonyLimit }

    var body: some View {
        ExplainerHeader(value: Format.monotony(snapshot.monotony), verdict: verdict, tint: tint, headline: headline)
        ChartCard(title: "The last seven days") {
            VStack(alignment: .leading, spacing: 12) {
                weekChart
                HStack(spacing: 16) {
                    LegendKey(color: Palette.ink.opacity(0.7), text: "Mean a day", dashed: true)
                    BandKey(text: "Spread either side")
                }
            }
        }
        if let week, let monotony = week.monotony {
            Worked(caption: "Spread is the standard deviation: how far a typical day sits from the mean.") {
                Equation(left: .init(label: "Mean a day", value: Format.load(week.mean)), symbol: "÷",
                         right: .init(label: "Spread", value: Format.load(week.spread)),
                         result: .init(label: "Monotony", value: Format.monotony(monotony)))
            }
        }
        if trend.count >= 7 {
            ChartCard(title: "Six weeks of it") { trendChart }
        }
        ExplainerSection(title: "What it is", text: "How alike your days are. The week's average daily load is divided by how much the days differ from it. Hard days followed by easy ones and rest give a low number; the same middling session every day gives a high one.")
        ExplainerSection(title: "Why it matters", text: "Fitness comes from the stress of a hard day and the recovery after it. A flat week gives the body nowhere to absorb the work, and in Carl Foster's studies of athletes, weeks above 2 went with illness and staleness even when the total was modest.")
        ExplainerSection(title: "What Cadence does", text: "The planner keeps at least one rest day, alternates upper and lower, and keeps hard runs off the days either side of a leg day, which is what keeps this low. Above 2, make the easy days easier rather than adding more.")
    }

    private var verdict: String {
        guard snapshot.monotony != nil else { return "No spread yet" }
        return isFlat ? "Too flat" : "Varied"
    }

    private var tint: Color {
        guard snapshot.monotony != nil else { return Palette.rest }
        return isFlat ? Palette.amber : Palette.sage
    }

    private var headline: String {
        guard snapshot.monotony != nil else {
            return "There is nothing to divide by until the days differ: a week of rest, or the same load every day, has no spread."
        }
        return isFlat
            ? "Every day this week has been much the same, so the hard ones have had nowhere to recover. An easy day or a rest day brings it down."
            : "Hard days are followed by easier ones, which is what lets the load be absorbed."
    }

    private var weekChart: some View {
        let calendar = coordinator.calendar
        let top = max(days.map(\.load).max() ?? 0, (week?.mean ?? 0) + (week?.spread ?? 0)) * 1.15
        return Chart {
            if let week, week.spread > 0 {
                RectangleMark(yStart: .value("Low", max(0, week.mean - week.spread)), yEnd: .value("High", week.mean + week.spread))
                    .foregroundStyle(Palette.ink.opacity(0.1))
            }
            ForEach(days) { day in
                BarMark(x: .value("Day", Format.shortWeekday.string(from: day.date)), y: .value("Load", day.load), width: .ratio(0.6))
                    .foregroundStyle(calendar.isDateInToday(day.date) ? Palette.today : Palette.accent)
                    .cornerRadius(4)
            }
            if let week {
                RuleMark(y: .value("Mean", week.mean))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .lineStyle(.init(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartYScale(domain: 0...max(top, 1))
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary) }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load each day for the last seven days")
        .accessibilityValue(days.map { "\(Format.weekday.string(from: $0.date)) \(Format.load($0.load))" }.joined(separator: ", "))
    }

    private var trendChart: some View {
        let top = max(3, (trend.compactMap(\.monotony).max() ?? 0) * 1.1)
        return Chart {
            RectangleMark(yStart: .value("Limit", LoadAnalysis.monotonyLimit), yEnd: .value("Top", top))
                .foregroundStyle(Palette.amber.opacity(0.08))
            RuleMark(y: .value("Limit", LoadAnalysis.monotonyLimit))
                .foregroundStyle(Palette.amber.opacity(0.8))
                .lineStyle(.init(lineWidth: 1.5, dash: [5, 5]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Too flat above 2").font(.label).foregroundStyle(Palette.amber)
                }
            ForEach(trend) { week in
                LineMark(x: .value("Day", week.date), y: .value("Monotony", week.monotony ?? 0))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(.init(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
            }
            if let last = trend.last, let monotony = last.monotony {
                PointMark(x: .value("Day", last.date), y: .value("Monotony", monotony))
                    .foregroundStyle(isFlat ? Palette.amber : Palette.accent)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: 0...top)
        .chartXAxis { weekAxis }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monotony of each seven days over the last six weeks")
        .accessibilityValue("Today \(Format.monotony(snapshot.monotony)). Above 2 is too flat.")
    }
}

// MARK: Strain

private struct StrainExplainer: View {
    let snapshot: LoadSnapshot

    /// Back-to-back weeks ending on the snapshot's day, oldest first.
    private var weeks: [WeeklyLoad] {
        let all = snapshot.weekly
        guard !all.isEmpty else { return [] }
        return stride(from: all.count - 1, through: 0, by: -7).prefix(8).map { all[$0] }.reversed()
    }
    /// The mean strain of the weeks before this one.
    private var usual: Double? {
        let earlier = weeks.dropLast().compactMap(\.strain)
        return earlier.count >= 2 ? earlier.reduce(0, +) / Double(earlier.count) : nil
    }
    private var share: Double? {
        guard let strain = snapshot.strain, let usual, usual > 0 else { return nil }
        return strain / usual
    }

    var body: some View {
        ExplainerHeader(value: snapshot.strain.map(Format.load) ?? "–", verdict: verdict, tint: tint, headline: headline)
        if weeks.count >= 2 {
            ChartCard(title: "Week by week") {
                VStack(alignment: .leading, spacing: 12) {
                    chart
                    HStack(spacing: 16) {
                        LegendKey(color: Palette.accent, text: "The last seven days")
                        if usual != nil { LegendKey(color: Palette.ink.opacity(0.7), text: "Your usual", dashed: true) }
                    }
                }
            }
        }
        if let monotony = snapshot.monotony, let strain = snapshot.strain {
            Worked(caption: "The same load counts for more in a flat week than a varied one.") {
                Equation(left: .init(label: "Week load", value: Format.load(snapshot.weekLoad)), symbol: "×",
                         right: .init(label: "Monotony", value: Format.monotony(monotony)),
                         result: .init(label: "Strain", value: Format.load(strain)))
            }
        }
        ExplainerSection(title: "What it is", text: "The week's total load weighed by its monotony. Two weeks with the same total can land very differently: spread over hard and easy days the body keeps up, packed flat it does not.")
        ExplainerSection(title: "Reading it", text: "There is no universal line for strain. What matters is a jump above your own usual weeks, especially with monotony near 2, which is when athletes in Carl Foster's studies most often fell ill.")
        ExplainerSection(title: "What Cadence does", text: "The planner sets each week's load from your chronic load, so strain only climbs as your base does. If it jumps anyway, an easy day back in the week brings both monotony and strain down.")
    }

    private var verdict: String {
        guard snapshot.strain != nil else { return "No spread yet" }
        guard let share else { return "Learning your usual" }
        return "\(Format.percent(share)) of usual"
    }

    private var tint: Color {
        guard let share else { return Palette.rest }
        return share > 1.25 ? Palette.amber : Palette.inkSecondary
    }

    private var headline: String {
        guard snapshot.strain != nil else {
            return "Strain is load times monotony, so it waits on a week where the days differ."
        }
        guard let share else { return "Load over the last seven days, weighed by how flat they were. A few weeks of logging gives it something to compare with." }
        if share > 1.25 { return "Well above your usual weeks: a big week, a flat one, or both. Keep the easy days easy." }
        if share < 0.75 { return "Well below your usual weeks. There is room to build." }
        return "In line with your usual weeks."
    }

    private var chart: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", Format.monthDay.string(from: week.date)), y: .value("Strain", week.strain ?? 0), width: .ratio(0.6))
                    .foregroundStyle(week.date == weeks.last?.date ? Palette.accent : Palette.accent.opacity(0.3))
                    .cornerRadius(4)
            }
            if let usual {
                RuleMark(y: .value("Usual", usual))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .lineStyle(.init(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartYScale(domain: 0...max(1, (weeks.compactMap(\.strain) + [usual ?? 0]).max() ?? 0) * 1.15)
        .chartXAxis {
            // Every other week, counting back from this one, so the dates have room.
            AxisMarks(values: weeks.reversed().enumerated().filter { $0.offset.isMultiple(of: 2) }.map { Format.monthDay.string(from: $0.element.date) }) { _ in
                AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strain for each of the last \(weeks.count) weeks")
        .accessibilityValue(weeks.map { "Week to \(Format.monthDay.string(from: $0.date)) \($0.strain.map(Format.load) ?? "none")" }.joined(separator: ", "))
    }
}

// MARK: Recovery

private struct RecoveryExplainer: View {
    let recovery: RecoveryStatus
    let lifting: RecoveryStatus.TodaysLifting

    private static let levels: [(RecoveryLevel, String)] = [
        (.recovered, "0 points"), (.fair, "1 point"), (.low, "2 or 3 points"), (.poor, "4 or more points"),
    ]

    /// What counts against today, from the signals that have a baseline to be judged against.
    private var points: Int { [recovery.hrv, recovery.restingHeartRate, recovery.sleep].compactMap { $0?.points }.reduce(0, +) }

    var body: some View {
        let tint = recovery.level.map(Palette.color(for:)) ?? Palette.rest
        ExplainerHeader(value: recovery.level?.displayName ?? "Learning",
                        verdict: recovery.level == nil ? "No baseline yet" : points == 1 ? "1 point" : "\(points) points",
                        tint: tint, headline: recovery.headline(lifting), isWord: true)
        ChartCard(title: "Today against your usual") {
            VStack(alignment: .leading, spacing: 20) {
                hrv
                resting
                sleep
                HStack(spacing: 16) {
                    BandKey(text: "Your usual", fill: Palette.sage.opacity(0.35))
                    LegendKey(color: Palette.amber, text: "Counts against today")
                }
            }
        }
        ExplainerSection(title: "What it is", text: "How well you have absorbed recent training, judged against your own history rather than population norms. Each signal that is off adds points: HRV below its range 2, resting heart rate up 3 bpm 1 and up 5 bpm 2, short sleep 1.")
        ExplainerSection(title: "The signals", text: "HRV is a week's average of the variability your watch measures overnight, against a band half a standard deviation either side of your mean over the 60 days before. One night is noise; a week below the band is a signal. Resting heart rate is the last three days against the 30 before. Sleep is short under 6 hours, or when the last three nights average an hour under your usual.")
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "What Cadence does")
            VStack(spacing: 4) {
                ForEach(Self.levels, id: \.0) { level, points in
                    LevelRow(name: level.displayName, detail: points, effect: effect(of: level),
                             tint: Palette.color(for: level), isCurrent: level == recovery.level)
                }
            }
            Text("Recovery trims today only, never the week: one morning says nothing about Saturday. A session with a set logged keeps its loads.")
                .font(.body2).foregroundStyle(Palette.inkSecondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func effect(of level: RecoveryLevel) -> String {
        level.loadMultiplier < 1 ? "Today's lifts \(Format.percent(1 - level.loadMultiplier)) lighter" : "Train as planned"
    }

    @ViewBuilder private var hrv: some View {
        if let signal = recovery.hrv {
            let range = signal.normalRange
            SignalRow(title: "HRV, 7 day", value: "\(Int(signal.current.rounded())) ms",
                      caption: range.map { "Usual \(Int($0.lowerBound.rounded())) to \(Int($0.upperBound.rounded())) ms" } ?? "Learning your range",
                      scale: Self.scale(around: [signal.current] + (range.map { [$0.lowerBound, $0.upperBound] } ?? []), pad: 0.2),
                      usual: range, current: signal.current, points: signal.points)
        } else {
            SignalRow.missing(title: "HRV, 7 day", caption: "Needs three days of readings from your watch")
        }
    }

    @ViewBuilder private var resting: some View {
        if let signal = recovery.restingHeartRate {
            let baseline = signal.baseline
            let scale = Self.scale(around: [signal.current] + (baseline.map { [$0 - 6, $0 + 8] } ?? []), pad: 0.08)
            SignalRow(title: "Resting heart rate, 3 day", value: "\(Int(signal.current.rounded())) bpm",
                      caption: baseline.map { "Usual \(Int($0.rounded())) bpm, counts from \(Int(($0 + 3).rounded()))" } ?? "Learning your usual",
                      scale: scale, usual: baseline.map { scale.lowerBound...($0 + 3) }, current: signal.current, points: signal.points)
        } else {
            SignalRow.missing(title: "Resting heart rate, 3 day", caption: "Needs two of the last three days from your watch")
        }
    }

    @ViewBuilder private var sleep: some View {
        if let signal = recovery.sleep {
            let scale = Self.scale(around: [signal.current, 4, 9] + (signal.baseline.map { [$0] } ?? []), pad: 0.05)
            SignalRow(title: "Sleep, last night", value: Format.sleep(signal.current),
                      caption: signal.baseline.map { "Usual \(Format.sleep($0)), short under 6 h" } ?? "Short under 6 h",
                      scale: scale, usual: 6...scale.upperBound, current: signal.current, points: signal.points)
        } else {
            SignalRow.missing(title: "Sleep, last night", caption: "No sleep recorded last night")
        }
    }

    /// A track wide enough for every value, padded by a share of its span.
    private static func scale(around values: [Double], pad: Double) -> ClosedRange<Double> {
        let low = values.min() ?? 0, high = values.max() ?? 1
        let margin = max(high - low, 1) * pad
        return (low - margin)...(high + margin)
    }
}

/// One recovery signal: its reading, and a track with the usual band and a marker at today.
private struct SignalRow: View {
    let title: String
    let value: String?
    let caption: String
    var scale: ClosedRange<Double> = 0...1
    var usual: ClosedRange<Double>?
    var current: Double?
    var points = 0

    static func missing(title: String, caption: String) -> SignalRow {
        SignalRow(title: title, value: nil, caption: caption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.label).foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 8)
                Text(value ?? "–").font(.numeralSmall).foregroundStyle(points > 0 ? Palette.amber : Palette.ink)
            }
            if current != nil { track }
            HStack {
                Text(caption).font(.label).foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 8)
                if points > 0 {
                    Text(points == 1 ? "1 point" : "\(points) points").font(.label).foregroundStyle(Palette.amber)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value ?? "No reading", caption, points > 0 ? "\(points) points against today" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07)).frame(height: 8)
                if let usual {
                    let start = x(usual.lowerBound, width), end = x(usual.upperBound, width)
                    Capsule().fill(Palette.sage.opacity(0.35)).frame(width: max(8, end - start), height: 8).offset(x: start)
                }
                if let current {
                    Circle()
                        .fill(points > 0 ? Palette.amber : .white)
                        .overlay { Circle().strokeBorder(Palette.surface, lineWidth: 3) }
                        .frame(width: 18, height: 18)
                        .offset(x: x(current, width) - 9)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
    }

    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(max(value, scale.lowerBound), scale.upperBound)
        return CGFloat((clamped - scale.lowerBound) / span) * width
    }
}

// MARK: Pieces

/// The figure's number and verdict, and a sentence on what it says today.
struct ExplainerHeader: View {
    let value: String
    let verdict: String
    let tint: Color
    let headline: String
    /// A level ("Low") rather than a number: medium weight, as words are.
    var isWord = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(value)
                    .font(isWord ? .cadence(size: 44, weight: .medium) : .numeralLarge)
                    .tracking(isWord ? -0.6 : 0)
                    .foregroundStyle(Palette.ink)
                StatusChip(text: verdict, tint: tint)
            }
            Text(headline)
                .font(.body2).foregroundStyle(Palette.inkSecondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.rowTitle).foregroundStyle(Palette.ink)
                content
            }
        }
    }
}

/// "How it is worked out", with today's own numbers.
private struct Worked<Content: View>: View {
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "How it is worked out")
            content
            Text(caption).font(.label).foregroundStyle(Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Two figures, the operator between them, and what they come to.
private struct Equation: View {
    struct Term {
        let label: String
        let value: String
    }

    let left: Term
    let symbol: String
    let right: Term
    let result: Term

    var body: some View {
        Card(cornerRadius: 18, padding: 14) {
            HStack(alignment: .bottom, spacing: 0) {
                term(left, tint: Palette.inkSecondary)
                operation(symbol)
                term(right, tint: Palette.inkSecondary)
                operation("=")
                term(result, tint: Palette.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left.label) \(left.value) \(symbol == "÷" ? "divided by" : "times") \(right.label) \(right.value) is \(result.label) \(result.value)")
    }

    private func term(_ term: Term, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term.label).font(.label).foregroundStyle(Palette.inkTertiary).lineLimit(1).minimumScaleFactor(0.8)
            Text(term.value).font(.numeralSmall).foregroundStyle(tint)
        }
        .fixedSize()
    }

    private func operation(_ symbol: String) -> some View {
        Text(symbol)
            .font(.cadence(size: 18, weight: .medium))
            .foregroundStyle(Palette.inkTertiary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 1)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text).font(.rowTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
    }
}

struct ExplainerSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: title)
            Text(text)
                .font(.body2).foregroundStyle(Palette.inkSecondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One step of a scale (a load zone, a recovery level) and what Cadence does there. Today's is lit.
private struct LevelRow: View {
    let name: String
    let detail: String
    let effect: String
    let tint: Color
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(tint.opacity(isCurrent ? 1 : 0.4)).frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.rowTitle).foregroundStyle(isCurrent ? Palette.ink : Palette.inkSecondary)
                    Spacer(minLength: 8)
                    Text(detail).font(.label.monospacedDigit()).foregroundStyle(Palette.inkTertiary)
                }
                Text(effect).font(.body2).foregroundStyle(isCurrent ? Palette.inkSecondary : Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isCurrent ? Palette.surface : .clear, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A filled swatch for a band, beside its name.
private struct BandKey: View {
    let text: String
    var fill: Color = Palette.ink.opacity(0.1)

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 14, height: 10)
            Text(text).font(.label).foregroundStyle(Palette.inkSecondary).lineLimit(1)
        }
    }
}

/// Date ticks a week apart.
private var weekAxis: some AxisContent {
    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
        AxisGridLine().foregroundStyle(Palette.hairline)
        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.axis).foregroundStyle(Palette.inkTertiary)
    }
}
