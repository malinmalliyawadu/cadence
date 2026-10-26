import Charts
import SwiftData
import SwiftUI
import TrainingEngine

/// The one chart that matters: acute load against chronic, with the ratio's zones.
struct LoadView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query(sort: \TrainingSession.date) private var sessions: [TrainingSession]
    @State private var window = 42

    private var snapshot: LoadSnapshot { coordinator.displaySnapshot(entries: sessions.compactMap(\.loadEntry)) }
    private var series: [DailyLoad] { Array(snapshot.series.suffix(window)) }
    private var byModality: [(date: Date, modality: Modality, load: Double)] {
        let start = coordinator.calendar.date(byAdding: .day, value: -window, to: coordinator.calendar.startOfDay(for: .now)) ?? .now
        return sessions.filter { $0.status == .completed && $0.date >= start }.map { (coordinator.calendar.startOfDay(for: $0.completedAt ?? $0.date), $0.modality, $0.load) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackdrop(modality: nil, intensity: 0.8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headline
                        if snapshot.series.allSatisfy({ $0.load == 0 }) {
                            emptyState
                        } else {
                            ratioChart
                            tiles
                            modalityChart
                            explainer
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .navigationTitle("Load")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Window", selection: $window) {
                        Text("4w").tag(28)
                        Text("6w").tag(42)
                        Text("12w").tag(84)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }

    private var headline: some View {
        let readiness = Readiness.from(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.ratio(snapshot.acwr))
                    .font(.numeralLarge)
                    .foregroundStyle(readiness.zone.tint)
                    .contentTransition(.numericText())
                Text(readiness.zone.displayName)
                    .font(.headline2)
                    .foregroundStyle(Palette.ink)
            }
            Text(readiness.headline)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private var ratioChart: some View {
        let zoneTop = series.map { max($0.acute, $0.chronic) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("Acute against chronic, 7 and 28 day").font(.headline).foregroundStyle(Palette.ink)
            Chart {
                ForEach(series) { day in
                    AreaMark(x: .value("Day", day.date), yStart: .value("Floor", 0), yEnd: .value("Acute", day.acute))
                        .foregroundStyle(LinearGradient(colors: [Palette.ember.opacity(0.55), Palette.ember.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", day.date), y: .value("Acute", day.acute))
                        .foregroundStyle(Palette.ember)
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
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: window >= 84 ? 14 : 7)) { _ in
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
            .chartLegend(.hidden)
            .frame(height: 220)
            HStack(spacing: 16) {
                legend(color: Palette.ember, text: "Acute \(Format.load(series.last?.acute ?? 0))")
                legend(color: Palette.ink.opacity(0.7), text: "Chronic \(Format.load(series.last?.chronic ?? 0))", dashed: true)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityLabel("Chart of acute training load against chronic training load over the last \(window) days. Ratio today \(Format.ratio(snapshot.acwr)).")
    }

    private func legend(color: Color, text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Rectangle().fill(color).frame(width: 18, height: 2).mask(HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Rectangle() } })
            } else {
                Capsule().fill(color).frame(width: 18, height: 3)
            }
            Text(text).font(.caption.weight(.medium)).foregroundStyle(Palette.inkSecondary)
        }
    }

    private var tiles: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(title: "This week", value: Format.load(snapshot.weekLoad), unit: "load")
                StatTile(title: "Monotony", value: snapshot.monotony.map { String(format: "%.1f", $0) } ?? "–", unit: snapshot.monotony.map { $0 > 2 ? "too flat" : "varied" } ?? "")
                StatTile(title: "Strain", value: snapshot.strain.map { Format.load($0) } ?? "–", unit: "")
            }
        }
    }

    private var modalityChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where the load comes from").font(.headline).foregroundStyle(Palette.ink)
            Chart(byModality, id: \.date) { entry in
                BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Load", entry.load))
                    .foregroundStyle(by: .value("Modality", entry.modality.displayName))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                Modality.strength.displayName: Palette.ember,
                Modality.running.displayName: Palette.sky,
                Modality.yoga.displayName: Palette.heat,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: window >= 84 ? 14 : 7)) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Palette.inkTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel().foregroundStyle(Palette.inkTertiary)
                }
            }
            .chartLegend(position: .bottom, spacing: 12)
            .frame(height: 170)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this is read").font(.headline).foregroundStyle(Palette.ink)
            Text("Every session becomes one number: how hard it felt, times how long it took. Lifting, running and yoga share the scale, so a long run can be weighed against a leg day. Acute is the last week, chronic the last month. Between 0.8 and 1.3 you are adapting; above 1.5 the week got ahead of your base and the planner pulls back.")
                .font(.footnote).foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No completed sessions yet").font(.headline).foregroundStyle(Palette.ink)
                Text("Log a few sessions and the ratio appears here. It needs about four weeks to settle into a baseline.")
                    .font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
            Text(value).font(.numeral).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.caption2.weight(.medium)).foregroundStyle(Palette.inkTertiary).frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
