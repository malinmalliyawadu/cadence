import SwiftData
import SwiftUI
import TrainingEngine

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query(sort: \TrainingSession.date) private var sessions: [TrainingSession]
    @Query(sort: \ForecastDay.date) private var forecasts: [ForecastDay]
    @State private var showSettings = false
    @State private var now = Date.now

    private var calendar: Calendar { coordinator.calendar }
    private var today: [TrainingSession] { sessions.filter { calendar.isDate($0.date, inSameDayAs: now) } }
    private var upNext: TrainingSession? { today.first { $0.status == .planned } ?? today.first }
    private var tomorrow: [TrainingSession] {
        guard let date = calendar.date(byAdding: .day, value: 1, to: now) else { return [] }
        return sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    private var forecastToday: DayForecast? { forecasts.first { calendar.isDate($0.date, inSameDayAs: now) }?.forecast }
    private var weekStart: Date { coordinator.weekStart(containing: now) }
    private var weekSessions: [TrainingSession] { sessions.filter { $0.weekStart == weekStart } }
    private var weekHasPlan: Bool { !weekSessions.isEmpty }
    private var snapshot: LoadSnapshot { coordinator.displaySnapshot(entries: sessions.compactMap(\.loadEntry), now: now) }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                if weekHasPlan {
                    plannedContent
                } else {
                    VStack(spacing: 0) {
                        header.padding(.horizontal, 20)
                        EmptyPlanView()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(for: TrainingSession.self) { SessionDetailView(session: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
        }
    }

    private var plannedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    conditions
                }
                activity
                plan
                if !tomorrow.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Tomorrow")
                        ForEach(tomorrow) { session in
                            NavigationLink(value: session) { SessionCard(session: session) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .statusBarScrim()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.dayMonth.string(from: now))
                    .font(.body2)
                    .foregroundStyle(Palette.inkSecondary)
                Text(summary)
                    .font(.title2)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 50, height: 50)
                    .background(Palette.raised, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    /// "Lower body and easy run", or "Rest day".
    private var summary: String {
        let titles = today.filter { $0.status != .skipped }.map(\.title)
        guard let first = titles.first else { return "Rest day" }
        return ([first] + titles.dropFirst().map { $0.lowercased() }).formatted(.list(type: .and))
    }

    private var conditions: some View {
        let zone = snapshot.zone
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let forecastToday {
                    Chip(symbol: forecastToday.condition.symbolName, text: "\(Format.temperature(forecastToday.tempMaxC)) \(forecastToday.condition.displayName)")
                    if forecastToday.precipitationProbability >= 0.3 {
                        Chip(symbol: "drop", text: "\(Format.percent(forecastToday.precipitationProbability)) rain")
                    }
                    if forecastToday.windKph >= 30 {
                        Chip(symbol: "wind", text: "\(Int(forecastToday.windKph)) km/h")
                    }
                }
                Chip(symbol: zone.symbolName, text: zone == .building ? "Building baseline" : zone.displayName, tint: zone.tint)
            }
        }
        .scrollClipDisabled()
    }

    private var activity: some View {
        let done = weekSessions.filter { $0.status == .completed }.count
        let counted = weekSessions.filter { $0.status != .skipped }.count
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your activity")
            HStack(spacing: 12) {
                StatCard(symbol: "waveform.path.ecg", title: "Load ratio", value: Format.ratio(snapshot.acwr), unit: snapshot.zone == .building ? "settling" : snapshot.zone.displayName.lowercased(), tint: snapshot.zone.tint)
                StatCard(symbol: "checkmark.circle", title: "Sessions", value: "\(done)", unit: "of \(counted) this week")
            }
            WeekLoadChart(days: weekDays, today: now, calendar: calendar)
        }
    }

    private var weekDays: [WeekLoadChart.Day] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let daySessions = weekSessions.filter { calendar.isDate($0.date, inSameDayAs: date) && $0.status != .skipped }
            let logged = daySessions.filter { $0.status == .completed }.map(\.load).reduce(0, +)
            let isPast = calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
            let planned = isPast ? 0 : daySessions.filter { $0.status == .planned }.map(\.load).reduce(0, +)
            return WeekLoadChart.Day(date: date, logged: logged, planned: planned)
        }
    }

    @ViewBuilder
    private var plan: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Today's plan")
            if today.isEmpty {
                Card {
                    HStack(spacing: 14) {
                        SessionTile(symbol: "moon.zzz.fill", tint: Palette.rest)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rest day").font(.rowTitle).foregroundStyle(Palette.ink)
                            Text("Walk, sleep, eat. The plan picks up tomorrow.")
                                .font(.body2).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            } else {
                ForEach(today.sorted { ($0 == upNext ? 0 : 1) < ($1 == upNext ? 0 : 1) }) { session in
                    NavigationLink(value: session) { SessionCard(session: session, isActive: session == upNext && session.status == .planned) }
                        .buttonStyle(.plain)
                }
            }
        }
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

/// One session as a card: thumbnail, title with its length, what it involves, and progress.
struct SessionCard: View {
    let session: TrainingSession
    var isActive = false
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    private var isDone: Bool { session.status == .completed }

    var body: some View {
        Card(isActive: isActive, padding: 14) {
            HStack(spacing: 14) {
                SessionTile(symbol: isDone ? "checkmark" : session.modality.symbolName, tint: isDone ? Palette.sage : session.modality.tint, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(session.title).font(.rowTitle).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(badge)
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(isDone ? Palette.sage : Palette.inkSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Palette.raised, in: .capsule)
                    }
                    Text(detail)
                        .font(.body2)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                    if session.modality == .strength, session.plannedSetCount > 0 {
                        ProgressBar(value: Double(session.loggedSetCount) / Double(session.plannedSetCount), tint: isDone ? Palette.sage : Palette.accent)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .opacity(session.status == .skipped ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(badge), \(detail)")
    }

    private var badge: String {
        switch session.status {
        case .completed: "Done"
        case .skipped: "Skipped"
        default: Format.minutes(session.plannedMinutes)
        }
    }

    private var detail: String {
        switch session.modality {
        case .strength:
            return isDone
                ? "\(session.loggedSetCount) sets, session RPE \(String(format: "%.1f", session.rpe ?? 0))"
                : "\(session.subtitle), \(session.orderedExercises.count) movements, \(session.plannedSetCount) sets"
        case .running:
            if isDone {
                let pace = session.actualPace.map { " at \(Format.pace($0)) /km" } ?? ""
                return "\(session.subtitle)\(pace), RPE \(Int((session.rpe ?? 0).rounded()))"
            }
            guard let kind = session.runKind else { return "Run" }
            let target = coordinator.runTarget(for: kind, asOf: session.date, in: context)
            guard let pace = target.pace else { return "Zone \(target.zone), run by feel" }
            return kind == .quality
                ? "20 min at \(Format.pace(pace)), zone \(target.zone)"
                : "\(Format.pace(pace)), zone \(target.zone)"
        case .yoga:
            return isDone ? "RPE \(Int((session.rpe ?? 0).rounded()))" : "Counts as recovery for the lifts around it"
        }
    }
}
