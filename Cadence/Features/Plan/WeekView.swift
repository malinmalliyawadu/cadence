import SwiftData
import SwiftUI
import TrainingEngine

struct WeekView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query(sort: \TrainingSession.date) private var sessions: [TrainingSession]
    @Query(sort: \ForecastDay.date) private var forecasts: [ForecastDay]
    @State private var weekOffset = 0
    @State private var confirmReplan = false
    @Namespace private var zoom

    private var calendar: Calendar { coordinator.calendar }
    private var weekStart: Date {
        calendar.date(byAdding: .day, value: 7 * weekOffset, to: coordinator.weekStart(containing: .now)) ?? .now
    }
    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var weekSessions: [TrainingSession] { sessions.filter { $0.weekStart == weekStart } }
    private var weekLoad: Double { weekSessions.filter { $0.status != .skipped }.map(\.load).reduce(0, +) }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if weekSessions.isEmpty {
                            emptyWeek
                        } else {
                            notes
                            VStack(spacing: 10) {
                                ForEach(days, id: \.self) { day in
                                    DayCard(date: day, sessions: weekSessions.filter { calendar.isDate($0.date, inSameDayAs: day) }, forecast: forecasts.first { calendar.isDate($0.date, inSameDayAs: day) }?.forecast, isToday: calendar.isDateInToday(day))
                                }
                            }
                            replanButton
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Week")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The toolbar draws the glass, as it does for every other header button.
                    MenuChip(title: "Week", selection: $weekOffset, options: [(0, "This week"), (1, "Next week")], glass: false)
                        .tint(Palette.ink)
                }
            }
            .zoomsSessions(in: zoom)
        }
    }

    private var header: some View {
        let done = weekSessions.filter { $0.status == .completed }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(Format.monthDay.string(from: weekStart)) to \(Format.monthDay.string(from: days.last ?? weekStart))")
                .font(.body2).foregroundStyle(Palette.inkSecondary)
            HStack(spacing: 12) {
                StatCard(symbol: "checkmark.circle", title: "Sessions", value: "\(done)", unit: "of \(weekSessions.count) done")
                StatCard(symbol: "flame", title: "Load", value: Format.load(weekLoad), unit: "units")
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if weekOffset == 0, let plan = coordinator.lastPlan, !plan.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.notes, id: \.self) { note in
                    Label(note, systemImage: "sparkle")
                        .font(.body2)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private var emptyWeek: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(weekOffset == 0 ? "Nothing planned yet." : "Next week is planned on Monday, or now if you want a head start.")
                .font(.system(size: 17)).foregroundStyle(Palette.inkSecondary)
            Button {
                Task { await coordinator.planWeek(containing: weekStart, in: context) }
            } label: {
                Label("Plan this week", systemImage: "sparkles")
            }
            .buttonStyle(.primary)
            .disabled(coordinator.phase == .planning)
        }
        .padding(.top, 40)
    }

    private var replanButton: some View {
        Button { confirmReplan = true } label: {
            Label("Re-plan remaining days", systemImage: "arrow.trianglehead.2.clockwise")
        }
        .buttonStyle(.secondary)
        .disabled(coordinator.phase == .planning || weekOffset == 1 && weekSessions.isEmpty)
        // On the button, so the popover points at it.
        .confirmationDialog("Re-plan this week?", isPresented: $confirmReplan, titleVisibility: .visible) {
            Button("Re-plan remaining days") { Task { await coordinator.planWeek(containing: weekStart, in: context) } }
        } message: {
            Text("Sessions you have already completed stay. Everything else is rebuilt from today's load and forecast.")
        }
    }
}

struct DayCard: View {
    let date: Date
    let sessions: [TrainingSession]
    let forecast: DayForecast?
    let isToday: Bool
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    /// Runs lead with their pace; everything else keeps its subtitle.
    private func detail(_ session: TrainingSession) -> String {
        guard session.modality == .running, let kind = session.runKind else { return session.subtitle }
        if session.status == .completed, let pace = session.actualPace { return "\(session.subtitle) at \(Format.pace(pace))" }
        guard session.status == .planned, let pace = coordinator.runTarget(for: kind, asOf: session.date, in: context).pace else { return session.subtitle }
        return "\(session.subtitle) at \(Format.pace(pace.fastest)) to \(Format.pace(pace.slowest))"
    }

    var body: some View {
        HStack(alignment: sessions.isEmpty ? .center : .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(Format.shortWeekday.string(from: date))
                    .font(.label)
                    .foregroundStyle(isToday ? Palette.today : Palette.inkSecondary)
                Text(Format.dayNumber.string(from: date))
                    .font(.numeral)
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 10) {
                if sessions.isEmpty {
                    HStack(spacing: 12) {
                        Text("Rest")
                            .font(.rowTitle)
                            .foregroundStyle(Palette.inkTertiary)
                        Spacer(minLength: 0)
                        RestDayButton(date: date)
                    }
                } else {
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            HStack(spacing: 12) {
                                SessionTile(symbol: session.status == .completed ? "checkmark" : session.modality.symbolName, tint: session.status == .completed ? Palette.sage : session.modality.tint, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title).font(.rowTitle).foregroundStyle(Palette.ink)
                                    Text(detail(session)).font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pressable)
                        .sessionZoomSource(session, cornerRadius: 12)
                        .opacity(session.status == .skipped ? 0.5 : 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let forecast {
                VStack(spacing: 3) {
                    Image(systemName: forecast.condition.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 20))
                    Text(Format.temperature(forecast.tempMaxC))
                        .font(.numeralSmall)
                        .foregroundStyle(Palette.ink)
                    if forecast.precipitationProbability >= 0.3 {
                        Text(Format.percent(forecast.precipitationProbability))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.sky)
                    }
                }
                .frame(width: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(forecast.condition.displayName), \(Format.temperature(forecast.tempMaxC)), \(Format.percent(forecast.precipitationProbability)) chance of rain")
            }
        }
        .padding(16)
        .surface(cornerRadius: 22)
    }
}

/// An icon, a title, and one number with its unit.
struct StatCard: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    var tint: Color = Palette.ink

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    IconDisc(symbol: symbol, tint: tint)
                    Text(title).font(.rowTitle).foregroundStyle(Palette.ink)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).font(.numeral).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text(unit).font(.body2).foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
