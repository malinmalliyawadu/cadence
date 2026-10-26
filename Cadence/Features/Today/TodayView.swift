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
    private var weekHasPlan: Bool {
        let start = coordinator.weekStart(containing: now)
        return sessions.contains { $0.weekStart == start }
    }
    private var snapshot: LoadSnapshot { coordinator.displaySnapshot(entries: sessions.compactMap(\.loadEntry), now: now) }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackdrop(modality: upNext?.modality, forecast: forecastToday, intensity: upNext?.status == .completed ? 0.55 : 1)
                if weekHasPlan {
                    plannedContent
                } else {
                    EmptyPlanView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(for: TrainingSession.self) { SessionDetailView(session: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
        }
    }

    private var plannedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                readinessStrip
                if let upNext {
                    primaryAction(for: upNext)
                    let others = today.filter { $0 != upNext }
                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Also today").font(.headline2).foregroundStyle(Palette.ink)
                            ForEach(others) { session in
                                NavigationLink(value: session) { SessionRow(session: session) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    restCard
                }
                if !tomorrow.isEmpty { tomorrowSection }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Format.dayMonth.string(from: now))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            if let upNext {
                DisplayText(text: upNext.title)
                Text(upNext.status == .completed ? "Done. \(upNext.subtitle)" : upNext.subtitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(upNext.modality.tint)
            } else {
                DisplayText(text: "Rest")
                Text("Nothing planned. Recovery is training.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    /// The one prominent surface on the screen: open the session, or see it is done.
    private func primaryAction(for session: TrainingSession) -> some View {
        NavigationLink(value: session) {
            HStack(spacing: 14) {
                ModalityBadge(symbol: session.status == .completed ? "checkmark" : session.modality.symbolName, tint: session.status == .completed ? Palette.sage : session.modality.tint, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.status == .completed ? "Logged" : session.status == .skipped ? "Skipped" : "Start session")
                        .font(.headline2).foregroundStyle(Palette.ink)
                    Text(sessionDetail(session))
                        .font(.subheadline).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if session.status == .planned {
                    Text(Format.minutes(session.plannedMinutes)).font(.numeralSmall).foregroundStyle(Palette.inkSecondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(Glass.regular.tint((session.status == .completed ? Palette.sage : session.modality.tint).opacity(0.22)).interactive(), in: .rect(cornerRadius: 26))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.status == .completed ? "Logged" : "Start") \(session.title), \(sessionDetail(session))")
    }

    private func sessionDetail(_ session: TrainingSession) -> String {
        switch session.modality {
        case .strength:
            return session.status == .completed ? "\(session.loggedSetCount) sets, session RPE \(String(format: "%.1f", session.rpe ?? 0))" : "\(session.subtitle), \(session.orderedExercises.count) movements, \(session.plannedSetCount) sets"
        case .running:
            return session.status == .completed ? "\(session.subtitle), RPE \(Int((session.rpe ?? 0).rounded()))" : (session.runKind == .easy ? "Conversational pace" : session.runKind == .long ? "Steady, finish strong" : "Threshold work in the middle")
        case .yoga:
            return session.status == .completed ? "RPE \(Int((session.rpe ?? 0).rounded()))" : "Counts as recovery for the lifts around it"
        }
    }

    private var readinessStrip: some View {
        let zone = snapshot.zone
        return ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassPill(symbol: zone.symbolName, text: zone == .building ? "Building baseline" : "\(zone.displayName) \(Format.ratio(snapshot.acwr))", tint: zone.tint)
                    if let forecastToday {
                        GlassPill(symbol: forecastToday.condition.symbolName, text: "\(Format.temperature(forecastToday.tempMaxC)) \(forecastToday.condition.displayName)", tint: Palette.sky)
                        if forecastToday.precipitationProbability >= 0.3 {
                            GlassPill(symbol: "drop.fill", text: "\(Format.percent(forecastToday.precipitationProbability)) rain", tint: Palette.sky)
                        }
                        if forecastToday.windKph >= 30 {
                            GlassPill(symbol: "wind", text: "\(Int(forecastToday.windKph)) km/h", tint: Palette.sky)
                        }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private var restCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                ModalityBadge(symbol: "moon.zzz.fill", tint: Palette.rest)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest day").font(.headline2).foregroundStyle(Palette.ink)
                    Text("Walk, sleep, eat. The plan picks up tomorrow.")
                        .font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private var tomorrowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tomorrow")
                .font(.headline2)
                .foregroundStyle(Palette.ink)
            ForEach(tomorrow) { session in
                NavigationLink(value: session) { SessionRow(session: session) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// One session as a quiet glass control.
struct SessionRow: View {
    let session: TrainingSession

    var body: some View {
        GlassRow {
            HStack(spacing: 14) {
                ModalityBadge(symbol: session.status == .completed ? "checkmark" : session.modality.symbolName, tint: session.status == .completed ? Palette.sage : session.modality.tint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if session.status == .planned {
                    Text(Format.minutes(session.plannedMinutes))
                        .font(.numeralSmall)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .opacity(session.status == .skipped ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(detail), \(session.status.rawValue)")
    }

    private var detail: String {
        switch session.modality {
        case .strength:
            return session.status == .completed ? "\(session.loggedSetCount) sets logged" : "\(session.subtitle), \(session.orderedExercises.count) movements"
        case .running, .yoga:
            return session.status == .completed ? "Done, RPE \(Int((session.rpe ?? 0).rounded()))" : session.subtitle
        }
    }
}
