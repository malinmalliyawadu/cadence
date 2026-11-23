import Charts
import SwiftData
import SwiftUI
import TrainingEngine

/// Race predictions, slid up from Home: the lead distance's time against the goal, how it has moved
/// over six months, every distance with its pace, and how the numbers are worked out.
struct RaceExplainer: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    var body: some View {
        let outlook = coordinator.raceOutlook(in: context)
        let lead = outlook.goal?.distance ?? .fiveK
        if let vdot = outlook.vdot, let predicted = outlook.predictedMinutes(for: lead) {
            let verdict = RaceVerdict(outlook)
            ExplainerHeader(value: Format.raceTime(predicted), verdict: verdict?.text ?? lead.displayName,
                            tint: verdict?.tint ?? Palette.inkTertiary, headline: headline(outlook, lead: lead, vdot: vdot))
            ChartCard(title: "Predicted \(lead.displayName), six months") {
                if outlook.history.count >= 2 {
                    chart(outlook, lead: lead)
                } else {
                    Text("The line draws once there are runs in two different weeks.")
                        .font(.body2).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Every distance")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(RaceDistance.allCases.enumerated()), id: \.element) { index, distance in
                            if index > 0 { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14) }
                            row(distance, outlook: outlook)
                        }
                    }
                }
            }
        } else {
            ExplainerSection(title: "No prediction yet", text: "Predictions come from your runs. Log a run of 3 km or more, or let Apple Health bring one in, and they show here.")
        }
        ExplainerSection(title: "How it is worked out", text: "Every run of 3 km or more gives a VDOT, Jack Daniels' measure of running fitness, from its pace and how long it lasted. The best of the last eight weeks is your fitness, since easy and long runs are run under it on purpose. A prediction is the time that fitness runs each distance in, flat out, on the same curves. A hard effort, a parkrun or a time trial, keeps it honest.")
        ExplainerSection(title: "The longer two", text: "The half and the marathon assume the mileage to go with the fitness. On a few runs a week, expect them to come in slower than this.")
        if coordinator.profile(in: context).runGoal != nil {
            ExplainerSection(title: "What the plan does", text: "With a goal set, the week's quality run turns over: intervals at VO2max pace, then threshold, then speed reps, one each week. The paces come from your fitness now, not the goal, since running at goal pace before you have the fitness for it is how sessions fall apart. As your runs get faster, the paces follow.")
        } else {
            ExplainerSection(title: "Setting a goal", text: "Set a 5 or 10 km goal in Settings and the week's quality run turns over between intervals, threshold and speed reps, and this shows how far off it you are.")
        }
    }

    private func headline(_ outlook: RaceOutlook, lead: RaceDistance, vdot: Double) -> String {
        guard let goal = outlook.goal else {
            return "Your best run of the last eight weeks puts a flat-out \(lead.displayName) at this. That is a VDOT of \(String(format: "%.1f", vdot))."
        }
        return "A VDOT of \(String(format: "%.1f", vdot)) from your best run of the last eight weeks. \(goal.distance.displayName) in \(Format.raceTime(goal.minutes)) takes \(String(format: "%.1f", goal.vdot)). \(Self.trendLine(outlook, goal: goal))"
    }

    /// Where the trend is heading against the goal, one sentence.
    static func trendLine(_ outlook: RaceOutlook, goal: RunGoal) -> String {
        if outlook.goalIsMet { return "You are already running \(Format.raceTime(goal.minutes)) shape. Time for a faster goal, or a race." }
        if let date = outlook.projectedDate {
            return "At the last twelve weeks' rate, \(Format.raceTime(goal.minutes)) comes around \(date.formatted(.dateTime.month(.wide).year()))."
        }
        guard let slope = outlook.vdotPerWeek else { return "A few more weeks of runs and this shows when the goal comes around." }
        return slope >= RaceOutlook.trendThreshold
            ? "Rising, but more than two years from \(Format.raceTime(goal.minutes)) at this rate."
            : "Holding steady over the last twelve weeks. Quality runs are what move it."
    }

    private func row(_ distance: RaceDistance, outlook: RaceOutlook) -> some View {
        let minutes = outlook.predictedMinutes(for: distance) ?? 0
        let isGoal = outlook.goal?.distance == distance
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(distance.displayName).font(.rowTitle).foregroundStyle(Palette.ink)
                Text(isGoal ? "Goal \(Format.raceTime(outlook.goal!.minutes))" : "\(Format.pace(minutes * 60 / distance.kilometres)) /km")
                    .font(.body2.monospacedDigit()).foregroundStyle(isGoal ? Palette.accent : Palette.inkSecondary)
            }
            Spacer(minLength: 8)
            Text(Format.raceTime(minutes)).font(.numeralSmall).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ outlook: RaceOutlook, lead: RaceDistance) -> some View {
        let points = outlook.history.map { (date: $0.date, minutes: RunPacing.predictedMinutes(distanceKm: lead.kilometres, vdot: $0.vdot)) }
        let values = points.map(\.minutes) + (outlook.goal.map { [$0.minutes] } ?? [])
        let ticks = Self.ticks(low: values.min() ?? 0, high: values.max() ?? 1)
        // Faster is better, so faster is up: time is plotted negated, on a range just wider than the
        // data and the goal, and labelled back as a time.
        return Chart {
            if let goal = outlook.goal {
                RuleMark(y: .value("Goal", -goal.minutes))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(.init(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("Goal \(Format.raceTime(goal.minutes))").font(.axis).foregroundStyle(Palette.accent)
                    }
            }
            ForEach(points, id: \.date) { point in
                LineMark(x: .value("Week", point.date), y: .value("Minutes", -point.minutes))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(.init(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
            }
            if let point = points.last {
                PointMark(x: .value("Week", point.date), y: .value("Minutes", -point.minutes))
                    .foregroundStyle(Palette.today)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: -(ticks.last ?? 1)...(-(ticks.first ?? 0)))
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks.map { -$0 }) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel { if let minutes = value.as(Double.self) { Text(Format.raceTime(-minutes)) } }
                    .font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.axis).foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Predicted \(lead.displayName) time each week over six months")
        .accessibilityValue(points.last.map { "Now \(Format.raceTime($0.minutes))" } ?? "")
    }

    /// Whole-minute ticks a step of 1, 2, 5, 10 or 30 minutes apart, the first at or under `low` and
    /// the last at or over `high`, with no more than five of them.
    static func ticks(low: Double, high: Double) -> [Double] {
        let steps: [Double] = [1, 2, 5, 10, 30]
        let step = steps.first { ((high / $0).rounded(.up) - (low / $0).rounded(.down)) <= 4 } ?? 60
        let first = (low / step).rounded(.down) * step
        let last = max(first + step, (high / step).rounded(.up) * step)
        return Array(stride(from: first, through: last, by: step))
    }
}
