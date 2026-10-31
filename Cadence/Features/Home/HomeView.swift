import SwiftData
import SwiftUI
import TrainingEngine

/// The dashboard. Top to bottom, in the order the athlete needs it: the session to start, how
/// loaded they are, the week so far, what is coming, and the longer trend underneath.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query(sort: \TrainingSession.date) private var sessions: [TrainingSession]
    @Query(sort: \ForecastDay.date) private var forecasts: [ForecastDay]
    @State private var showSettings = false
    @State private var now = Date.now
    @State private var window = 42
    @State private var explainer: Explainer?
    @Namespace private var zoom

    private var calendar: Calendar { coordinator.calendar }
    private var startOfToday: Date { calendar.startOfDay(for: now) }
    private var today: [TrainingSession] { sessions.filter { calendar.isDate($0.date, inSameDayAs: now) } }
    private var loggedToday: [TrainingSession] { today.filter { $0.status == .completed } }
    private var weekStart: Date { coordinator.weekStart(containing: now) }
    private var weekSessions: [TrainingSession] { sessions.filter { $0.weekStart == weekStart } }
    private var weekHasPlan: Bool { !weekSessions.isEmpty }
    private var snapshot: LoadSnapshot { coordinator.displaySnapshot(entries: sessions.compactMap(\.loadEntry), now: now) }
    /// Today's recovery, once Apple Health has been read today.
    private var recovery: RecoveryStatus? { coordinator.recovery.flatMap { calendar.isDate($0.asOf, inSameDayAs: now) ? $0 : nil } }
    private var todaysLifting: RecoveryStatus.TodaysLifting {
        let lifts = today.filter { $0.modality == .strength && $0.status == .planned }
        if lifts.contains(where: { $0.loggedSetCount == 0 && $0.recoveryFactor < 1 }) { return .trimmed }
        if lifts.contains(where: { $0.loggedSetCount > 0 }) { return .started }
        return .none
    }

    /// Planned sessions from today on, a strength session already under way first.
    private var ahead: [TrainingSession] {
        sessions
            .filter { $0.status == .planned && $0.date >= startOfToday }
            .sorted { lhs, rhs in
                let l = calendar.startOfDay(for: lhs.date), r = calendar.startOfDay(for: rhs.date)
                if l != r { return l < r }
                return lhs.loggedSetCount > rhs.loggedSetCount
            }
    }
    private var upNext: TrainingSession? { ahead.first }
    private var upNextIsToday: Bool { upNext.map { calendar.isDate($0.date, inSameDayAs: now) } ?? false }
    private var comingUp: [TrainingSession] { Array(ahead.dropFirst().prefix(3)) }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                if weekHasPlan {
                    dashboard
                } else {
                    VStack(spacing: 0) {
                        header.padding(.horizontal, Metrics.gutter)
                        EmptyPlanView()
                    }
                }
            }
            // The greeting is part of the page and scrolls away with it; the bar keeps only its
            // buttons, so nothing takes its place as an inline title.
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
                        // Toolbar controls stay white like the back button; violet marks what is active.
                        .tint(Palette.ink)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $explainer) { ExplainerSheet(explainer: $0, snapshot: snapshot, recovery: recovery, lifting: todaysLifting) }
            .zoomsSessions(in: zoom)
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    hero
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Readiness")
                    ReadinessCard(snapshot: snapshot, recovery: recovery, lifting: todaysLifting) { explainer = $0 }
                    tiles
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "This week")
                    WeekLoadChart(days: weekDays, today: now, calendar: calendar)
                }
                if !comingUp.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Coming up")
                        VStack(spacing: 0) {
                            ForEach(Array(comingUp.enumerated()), id: \.element.id) { index, session in
                                if index > 0 { Divider().overlay(Palette.hairline).padding(.leading, 70) }
                                NavigationLink(value: session) { UpcomingRow(session: session, now: now) }
                                    .buttonStyle(.pressable)
                                    .sessionZoomSource(session, cornerRadius: 22)
                            }
                        }
                        .surface()
                    }
                }
                trends
                howLoadIsRead
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 40)
        }
    }

    // MARK: Header and hero

    /// The greeting, set as the other tabs' large titles are, with the date and weather under it.
    private var header: some View {
        // Spaced as Week's date range sits under its title.
        VStack(alignment: .leading, spacing: 9) {
            Text(greeting)
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            dateLine
        }
    }

    /// Under the greeting, as the date range sits under Week's title.
    private var dateLine: some View {
        HStack(spacing: 8) {
            Text(Format.dayMonth.string(from: now))
            if let forecast = forecast(on: now) {
                HStack(spacing: 4) {
                    Image(systemName: forecast.condition.symbolName).symbolRenderingMode(.multicolor)
                    Text(Format.temperature(forecast.tempMaxC)).monospacedDigit()
                }
                .accessibilityLabel("\(Format.temperature(forecast.tempMaxC)), \(forecast.condition.displayName)")
            }
        }
        .font(.body2)
        .foregroundStyle(Palette.inkSecondary)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        switch calendar.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let upNext, upNextIsToday {
            UpNextCard(session: upNext, isToday: true, forecast: forecast(on: upNext.date))
            if !loggedToday.isEmpty { DayDoneCard(date: now, logged: loggedToday) }
        } else {
            DayDoneCard(date: now, logged: loggedToday)
            if let upNext {
                UpNextCard(session: upNext, isToday: false, forecast: forecast(on: upNext.date))
            }
        }
    }

    private func forecast(on date: Date) -> DayForecast? {
        forecasts.first { calendar.isDate($0.date, inSameDayAs: date) }?.forecast
    }

    // MARK: Load

    private var tiles: some View {
        let done = weekSessions.filter { $0.status == .completed }.count
        let counted = weekSessions.filter { $0.status != .skipped }.count
        let monotony = snapshot.monotony
        let isFlat = (monotony ?? 0) > LoadAnalysis.monotonyLimit
        return HStack(spacing: 10) {
            StatTile(title: "Sessions", value: "\(done)", unit: "of \(counted) this week")
            Button { explainer = .monotony } label: {
                StatTile(title: "Monotony", value: Format.monotony(monotony),
                         unit: monotony.map { _ in isFlat ? "too flat" : "varied" } ?? "",
                         tint: isFlat ? Palette.amber : Palette.inkTertiary, explains: true)
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Explains monotony")
            Button { explainer = .strain } label: {
                StatTile(title: "Strain", value: snapshot.strain.map { Format.load($0) } ?? "–", unit: "last 7 days", explains: true)
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Explains strain")
        }
    }

    private var weekDays: [WeekLoadChart.Day] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let daySessions = weekSessions.filter { calendar.isDate($0.date, inSameDayAs: date) && $0.status != .skipped }
            let logged = daySessions.filter { $0.status == .completed }.map(\.load).reduce(0, +)
            let isPast = calendar.startOfDay(for: date) < startOfToday
            let planned = isPast ? 0 : daySessions.filter { $0.status == .planned }.map(\.load).reduce(0, +)
            return WeekLoadChart.Day(date: date, logged: logged, planned: planned)
        }
    }

    private var series: [DailyLoad] { Array(snapshot.series.suffix(window)) }

    private var byModality: [(date: Date, modality: Modality, load: Double)] {
        let start = calendar.date(byAdding: .day, value: -window, to: startOfToday) ?? now
        return sessions
            .filter { $0.status == .completed && $0.date >= start }
            .map { (calendar.startOfDay(for: $0.completedAt ?? $0.date), $0.modality, $0.load) }
    }

    @ViewBuilder
    private var trends: some View {
        if !snapshot.series.allSatisfy({ $0.load == 0 }) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Trend") {
                    MenuChip(title: "Window", selection: $window, options: [(28, "4 weeks"), (42, "6 weeks"), (84, "12 weeks")])
                }
                LoadTrendCard(series: series, window: window) { explainer = .trainingLoad }
                LoadMixCard(entries: byModality, window: window)
            }
        }
    }

    private var howLoadIsRead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How load is read").font(.rowTitle).foregroundStyle(Palette.ink)
            Text("Every session becomes one number: how hard it felt, times how long it took. Lifting, running and yoga share the scale, so a long run can be weighed against a leg day. Acute is the last week, chronic the last month. Between 0.8 and 1.3 you are adapting; above 1.5 the week got ahead of your base and the planner pulls back.")
                .font(.body2).foregroundStyle(Palette.inkTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

/// A later session as a compact row: its day, what it is, and the number that matters for it.
struct UpcomingRow: View {
    let session: TrainingSession
    let now: Date
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    var body: some View {
        HStack(spacing: 14) {
            SessionTile(symbol: session.modality.symbolName, tint: session.modality.tint, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.rowTitle).foregroundStyle(Palette.ink).lineLimit(1)
                Text(detail).font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(day)
                .font(.label)
                .foregroundStyle(Palette.inkSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var day: String {
        let calendar = coordinator.calendar
        if calendar.isDate(session.date, inSameDayAs: now) { return "Later" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(session.date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return Format.shortWeekday.string(from: session.date)
    }

    private var detail: String {
        switch session.modality {
        case .strength:
            return "\(session.subtitle), \(session.plannedSetCount) sets"
        case .running:
            guard let kind = session.runKind, let pace = coordinator.runTarget(for: kind, asOf: session.date, in: context).pace else { return session.subtitle }
            return "\(session.subtitle) at \(Format.pace(pace.fastest)) to \(Format.pace(pace.slowest))"
        case .yoga:
            return session.subtitle
        }
    }
}
