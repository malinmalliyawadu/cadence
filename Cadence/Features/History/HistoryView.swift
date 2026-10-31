import SwiftData
import SwiftUI
import TrainingEngine

/// What has been done: every finished session, newest first, and every movement lifted with
/// the way it is heading. A session opens as it was logged; a movement opens onto its trend.
struct HistoryView: View {
    enum Page: Hashable { case sessions, movements }

    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query(filter: #Predicate<TrainingSession> { $0.statusRaw == "completed" }, sort: \TrainingSession.date, order: .reverse)
    private var sessions: [TrainingSession]
    @Query private var profiles: [AthleteProfile]
    @State private var page: Page = .sessions
    /// Nil shows every modality.
    @State private var modality: Modality?
    @State private var search = ""
    /// Worked out in the background when the finished sessions change. Nil until the first pass.
    @State private var history: MovementHistory?
    @Namespace private var zoom

    private var bodyweight: Double { profiles.first?.bodyweightKg ?? 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ChipPicker(title: "Show", selection: $page, options: [(.sessions, "Sessions"), (.movements, "Movements")])
                        switch page {
                        case .sessions: SessionLog(sessions: shownSessions, bests: history?.bests ?? [:], calendar: coordinator.calendar, isFiltered: isFiltered)
                        case .movements:
                            if let history { MovementList(movements: shownMovements(history), isFiltered: !search.isEmpty) }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: page == .sessions ? "Session or movement" : "Movement")
            .toolbar {
                if page == .sessions {
                    ToolbarItem(placement: .topBarTrailing) {
                        // The toolbar draws the glass, as it does for every other header button.
                        MenuChip(title: "Sessions", selection: $modality, options: [
                            (nil, "All"), (.strength, "Lifting"), (.running, "Runs"), (.yoga, "Yoga"),
                        ], glass: false)
                        .tint(Palette.ink)
                    }
                }
            }
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
            .zoomsSessions(in: zoom)
            .task(id: MovementHistory.Inputs(sessions: sessions.map(\.id), bodyweightKg: bodyweight)) {
                history = await HistoryReader.history(in: context, bodyweightKg: bodyweight)
            }
        }
    }

    private var isFiltered: Bool { modality != nil || !search.isEmpty }

    private var shownSessions: [TrainingSession] {
        sessions.filter { session in
            (modality == nil || session.modality == modality)
                && (search.isEmpty || session.title.localizedCaseInsensitiveContains(search)
                    || session.exercises.contains { $0.name.localizedCaseInsensitiveContains(search) })
        }
    }

    private func shownMovements(_ history: MovementHistory) -> [MovementHistory.Movement] {
        search.isEmpty ? history.movements : history.movements.filter { $0.exercise.name.localizedCaseInsensitiveContains(search) }
    }
}

// MARK: Sessions

/// Finished sessions by month, newest first.
private struct SessionLog: View {
    let sessions: [TrainingSession]
    let bests: [TrainingSession.ID: Int]
    let calendar: Calendar
    let isFiltered: Bool

    private var months: [(start: Date, sessions: [TrainingSession])] {
        var months: [(start: Date, sessions: [TrainingSession])] = []
        for session in sessions {
            let start = calendar.dateInterval(of: .month, for: session.date)?.start ?? session.date
            if months.last?.start == start { months[months.count - 1].sessions.append(session) } else { months.append((start, [session])) }
        }
        return months
    }

    var body: some View {
        if sessions.isEmpty {
            EmptyHistory(text: isFiltered ? "No finished sessions match." : "Nothing finished yet. Sessions land here as you finish them, along with runs and yoga from Apple Health.")
        } else {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(months, id: \.start) { month in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: Format.monthYear.string(from: month.start))
                        VStack(spacing: 8) {
                            ForEach(month.sessions) { session in
                                NavigationLink(value: session) { SessionLogRow(session: session, bests: bests[session.id] ?? 0) }
                                    .buttonStyle(.pressable)
                                    .sessionZoomSource(session, cornerRadius: 18)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A finished session: its day, what it was, and the gist of what was done.
private struct SessionLogRow: View {
    let session: TrainingSession
    let bests: Int

    private var detail: String {
        switch session.modality {
        case .strength:
            var parts = session.loggedSetCount > 0 ? ["\(session.loggedSetCount) sets"] : [session.subtitle]
            if let minutes = session.actualMinutes { parts.append(Format.minutes(minutes)) }
            return parts.joined(separator: ", ")
        case .running:
            guard let distance = session.distanceKm else { return Format.minutes(session.actualMinutes ?? session.plannedMinutes) }
            return session.actualPace.map { String(format: "%.1f km at %@ /km", distance, Format.pace($0)) } ?? String(format: "%.1f km", distance)
        case .yoga:
            return Format.minutes(session.actualMinutes ?? session.plannedMinutes)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(Format.shortWeekday.string(from: session.date)).font(.label).foregroundStyle(Palette.inkSecondary)
                Text(Format.dayNumber.string(from: session.date)).font(.numeral).foregroundStyle(Palette.ink)
            }
            .frame(width: 44)
            SessionTile(symbol: session.modality.symbolName, tint: session.modality.tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.rowTitle).foregroundStyle(Palette.ink)
                Text(detail).font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                if bests > 0 {
                    Label(bests == 1 ? "1 best" : "\(bests) bests", systemImage: "star.fill")
                        .font(.label)
                        .foregroundStyle(Palette.amber)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Movements

/// Every movement logged, the most recent first, each with its estimated max and its trend.
private struct MovementList: View {
    let movements: [MovementHistory.Movement]
    let isFiltered: Bool

    var body: some View {
        if movements.isEmpty {
            EmptyHistory(text: isFiltered ? "No logged movement matches." : "Nothing lifted yet. Each movement shows up here once you log it, with how its strength is trending.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Estimated max, and how it has moved over the last three months.")
                    .font(.body2).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVStack(spacing: 8) {
                    ForEach(movements) { movement in
                        NavigationLink(value: movement.exercise) { MovementRow(movement: movement) }
                            .buttonStyle(.pressable)
                    }
                }
            }
        }
    }
}

private struct MovementRow: View {
    let movement: MovementHistory.Movement

    private var latest: ExerciseTrendPoint? { movement.points.last }
    private var summary: ExerciseTrendSummary? {
        ExerciseTrend.summary(of: movement.points, metric: .oneRepMax, since: Calendar.current.date(byAdding: .month, value: -3, to: .now))
    }

    var body: some View {
        HStack(spacing: 12) {
            MovementThumbnail(exercise: movement.exercise, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(movement.exercise.name).font(.rowTitle).foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let latest {
                    Text("\(Format.monthDay.string(from: latest.date)), \(Format.set(latest.topSet))")
                        .font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let latest {
                    Text("\(Format.estimate(latest.oneRepMax)) kg").font(.numeralSmall).foregroundStyle(Palette.ink)
                }
                if let summary {
                    TrendChange(summary: summary, metric: .oneRepMax)
                }
            }
            .fixedSize()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// "+4.5 kg" in the colour of where it is heading: sage climbing, amber slipping.
struct TrendChange: View {
    let summary: ExerciseTrendSummary
    let metric: TrendMetric

    var body: some View {
        Label(Format.change(summary.change, metric: metric), systemImage: symbol)
            .labelStyle(TrendChangeLabelStyle())
            .font(.label.monospacedDigit())
            .foregroundStyle(summary.direction.tint)
    }

    private var symbol: String {
        switch summary.direction {
        case .climbing: "arrow.up.right"
        case .slipping: "arrow.down.right"
        case .holding, nil: "arrow.right"
        }
    }
}

private struct TrendChangeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}

private struct EmptyHistory: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.cadence(size: 17)).foregroundStyle(Palette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 40)
    }
}

extension Optional where Wrapped == TrendDirection {
    /// Climbing in sage, slipping in amber; holding, or too few sessions to say, stays quiet.
    var tint: Color {
        switch self {
        case .climbing: Palette.sage
        case .slipping: Palette.amber
        case .holding, nil: Palette.inkSecondary
        }
    }
}

extension TrendDirection {
    var displayName: String {
        switch self {
        case .climbing: "Climbing"
        case .holding: "Holding"
        case .slipping: "Slipping"
        }
    }
}
