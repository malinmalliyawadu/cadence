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

    private var calendar: Calendar { coordinator.calendar }
    private var weekStart: Date {
        calendar.date(byAdding: .day, value: 7 * weekOffset, to: coordinator.weekStart(containing: .now)) ?? .now
    }
    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var weekSessions: [TrainingSession] { sessions.filter { $0.weekStart == weekStart } }
    private var weekLoad: Double { weekSessions.filter { $0.status != .skipped }.map(\.load).reduce(0, +) }
    private var dominant: Modality? {
        let today = weekSessions.first { calendar.isDate($0.date, inSameDayAs: .now) && $0.status == .planned }
        return today?.modality ?? weekSessions.first { $0.status == .planned }?.modality
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackdrop(modality: dominant, intensity: 0.7)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if weekSessions.isEmpty {
                            emptyWeek
                        } else {
                            notes
                            GlassEffectContainer(spacing: 10) {
                                VStack(spacing: 10) {
                                    ForEach(days, id: \.self) { day in
                                        DayCard(date: day, sessions: weekSessions.filter { calendar.isDate($0.date, inSameDayAs: day) }, forecast: forecasts.first { calendar.isDate($0.date, inSameDayAs: day) }?.forecast, isToday: calendar.isDateInToday(day))
                                    }
                                }
                            }
                            replanButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .navigationTitle(weekOffset == 0 ? "This week" : "Next week")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Week", selection: $weekOffset) {
                        Text("This").tag(0)
                        Text("Next").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: TrainingSession.self) { SessionDetailView(session: $0) }
            .confirmationDialog("Re-plan this week?", isPresented: $confirmReplan, titleVisibility: .visible) {
                Button("Re-plan remaining days") { Task { await coordinator.planWeek(containing: weekStart, in: context) } }
            } message: {
                Text("Sessions you have already completed stay. Everything else is rebuilt from today's load and forecast.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Format.monthDay.string(from: weekStart)) to \(Format.monthDay.string(from: days.last ?? weekStart))")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Palette.inkSecondary)
                Text("\(weekSessions.filter { $0.status == .completed }.count) of \(weekSessions.count) done")
                    .font(.headline).foregroundStyle(Palette.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.load(weekLoad)).font(.numeral).foregroundStyle(Palette.ink)
                Text("load units").font(.caption.weight(.medium)).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if weekOffset == 0, let plan = coordinator.lastPlan, !plan.notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.notes, id: \.self) { note in
                    Label(note, systemImage: "sparkle")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private var emptyWeek: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(weekOffset == 0 ? "Nothing planned yet." : "Next week is planned on Monday, or now if you want a head start.")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.inkSecondary)
            Button {
                Task { await coordinator.planWeek(containing: weekStart, in: context) }
            } label: {
                Label("Plan this week", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(coordinator.phase == .planning)
        }
        .padding(.top, 40)
    }

    private var replanButton: some View {
        Button { confirmReplan = true } label: {
            Label("Re-plan remaining days", systemImage: "arrow.trianglehead.2.clockwise")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .disabled(coordinator.phase == .planning || weekOffset == 1 && weekSessions.isEmpty)
    }
}

struct DayCard: View {
    let date: Date
    let sessions: [TrainingSession]
    let forecast: DayForecast?
    let isToday: Bool

    var body: some View {
        HStack(alignment: sessions.isEmpty ? .center : .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(Format.shortWeekday.string(from: date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Palette.ember : Palette.inkSecondary)
                Text(Format.dayNumber.string(from: date))
                    .font(.numeral)
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 8) {
                if sessions.isEmpty {
                    Text("Rest")
                        .font(.headline)
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            HStack(spacing: 10) {
                                ModalityBadge(symbol: session.status == .completed ? "checkmark" : session.modality.symbolName, tint: session.status == .completed ? Palette.sage : session.modality.tint, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.title).font(.headline).foregroundStyle(Palette.ink)
                                    Text(session.subtitle).font(.footnote).foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.inkTertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
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
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.sky)
                    }
                }
                .frame(width: 48)
                .accessibilityLabel("\(forecast.condition.displayName), \(Format.temperature(forecast.tempMaxC)), \(Format.percent(forecast.precipitationProbability)) chance of rain")
            }
        }
        .padding(16)
        .glassEffect(isToday ? Glass.regular.tint(Palette.ember.opacity(0.14)) : .regular, in: .rect(cornerRadius: 24))
    }
}
