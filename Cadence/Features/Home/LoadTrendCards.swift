import Charts
import SwiftUI
import TrainingEngine

/// Acute load against chronic over the chosen window, with today's point in its zone's colour.
struct LoadTrendCard: View {
    let series: [DailyLoad]
    let window: Int
    var onExplain: () -> Void = {}

    var body: some View {
        let zoneTop = series.map { max($0.acute, $0.chronic) }.max() ?? 1
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onExplain) {
                HStack(spacing: 10) {
                    TitleIcon(symbol: "waveform.path.ecg")
                    Text("Acute against chronic").font(.rowTitle).foregroundStyle(Palette.ink)
                    InfoGlyph()
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Acute against chronic")
            .accessibilityHint("Explains training load")
            Chart {
                ForEach(series) { day in
                    AreaMark(x: .value("Day", day.date), yStart: .value("Floor", 0), yEnd: .value("Acute", day.acute))
                        .foregroundStyle(Palette.accent.opacity(0.16))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", day.date), y: .value("Acute", day.acute))
                        .foregroundStyle(Palette.accent)
                        .lineStyle(.init(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", day.date), y: .value("Chronic", day.chronic), series: .value("Series", "Chronic"))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .lineStyle(.init(lineWidth: 2, dash: [5, 5]))
                        .interpolationMethod(.catmullRom)
                }
                if let last = series.last, let acwr = last.acwr {
                    PointMark(x: .value("Day", last.date), y: .value("Acute", last.acute))
                        .foregroundStyle(LoadZone.zone(for: acwr).tint)
                        .symbolSize(90)
                }
            }
            .chartYScale(domain: 0...(zoneTop * 1.25))
            .chartXAxis { dayAxis(window: window) }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chart of acute training load against chronic training load over the last \(window) days.")
            .accessibilityValue("Acute \(Format.load(series.last?.acute ?? 0)), chronic \(Format.load(series.last?.chronic ?? 0)).")
            HStack(spacing: 16) {
                LegendKey(color: Palette.accent, text: "Acute, 7 day")
                LegendKey(color: Palette.ink.opacity(0.7), text: "Chronic, 28 day", dashed: true)
            }
        }
        .padding(16)
        .surface()
        .accessibilityElement(children: .contain)
    }
}

/// Completed load per day, stacked by modality, so a heavy week shows where it came from.
struct LoadMixCard: View {
    let entries: [(date: Date, modality: Modality, load: Double)]
    let window: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TitleIcon(symbol: "chart.bar")
                Text("Where the load comes from").font(.rowTitle).foregroundStyle(Palette.ink)
            }
            Chart(entries, id: \.date) { entry in
                BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Load", entry.load))
                    .foregroundStyle(by: .value("Modality", entry.modality.displayName))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                Modality.strength.displayName: Palette.strength,
                Modality.running.displayName: Palette.sky,
                Modality.yoga.displayName: Palette.orchid,
            ])
            .chartXAxis { dayAxis(window: window) }
            // The bars run to the card's edge; room at the end keeps the last date whole.
            .chartXScale(range: .plotDimension(endPadding: 36))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel().font(.axis).foregroundStyle(Palette.inkTertiary)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 150)
            HStack(spacing: 16) {
                ForEach([Modality.strength, .running, .yoga].filter { m in entries.contains { $0.modality == m } }, id: \.self) { modality in
                    LegendKey(color: modality.tint, text: "\(modality.displayName) \(share(of: modality))")
                }
            }
        }
        .padding(16)
        .surface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load by modality over the last \(window) days")
        .accessibilityValue([Modality.strength, .running, .yoga].map { "\($0.displayName) \(share(of: $0))" }.joined(separator: ", "))
    }

    private func share(of modality: Modality) -> String {
        let total = entries.map(\.load).reduce(0, +)
        guard total > 0 else { return "0%" }
        return Format.percent(entries.filter { $0.modality == modality }.map(\.load).reduce(0, +) / total)
    }
}

/// Date ticks every week, or every fortnight on the long window, each label centred on its tick.
private func dayAxis(window: Int) -> some AxisContent {
    AxisMarks(values: .stride(by: .day, count: window >= 84 ? 14 : 7)) { _ in
        AxisGridLine().foregroundStyle(Palette.hairline)
        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.axis).foregroundStyle(Palette.inkTertiary)
    }
}

/// A short line in the series' colour, then its name.
struct LegendKey: View {
    let color: Color
    let text: String
    var dashed = false

    var body: some View {
        HStack(spacing: 6) {
            if dashed {
                Rectangle().fill(color).frame(width: 18, height: 2).mask(HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Rectangle() } })
            } else {
                Capsule().fill(color).frame(width: 14, height: 4)
            }
            Text(text).font(.label.monospacedDigit()).foregroundStyle(Palette.inkSecondary).lineLimit(1)
        }
    }
}

/// A title, one number, and a word on what it means.
struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    var tint: Color = Palette.inkTertiary
    /// Tapping it opens an explainer.
    var explains = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.label).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                if explains { InfoGlyph() }
            }
            Text(value).font(.numeral).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(unit).font(.cadence(size: 12, weight: .medium)).foregroundStyle(tint).lineLimit(1).frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}
