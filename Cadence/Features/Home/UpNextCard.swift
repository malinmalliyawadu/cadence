import SwiftData
import SwiftUI
import TrainingEngine

/// The top of Home: the session to do next, what it involves, and the one blue button that opens
/// it. A session already started says how far it got and resumes. A session on a later day is
/// shown with a quieter button, since there is nothing to start today.
struct UpNextCard: View {
    let session: TrainingSession
    let isToday: Bool
    var forecast: DayForecast?
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator

    private var isStarted: Bool { session.modality == .strength && session.loggedSetCount > 0 }
    private static let padding: CGFloat = 18

    var body: some View {
        Card(isActive: isToday, cornerRadius: 26, padding: Self.padding) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    SessionTile(symbol: session.modality.symbolName, tint: session.modality.tint, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(eyebrow)
                            .font(.label)
                            .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
                        Text(Format.minutes(session.plannedMinutes))
                            .font(.label.monospacedDigit())
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    ChangeSessionMenu(session: session)
                }

                VStack(alignment: .leading, spacing: 6) {
                    DisplayText(text: session.title, size: 34)
                    Text(detail)
                        .font(.body2)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content

                if isStarted {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressBar(value: Double(session.loggedSetCount) / Double(max(1, session.plannedSetCount)))
                        Text("\(session.loggedSetCount) of \(session.plannedSetCount) sets logged")
                            .font(.label.monospacedDigit())
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                if isToday {
                    NavigationLink(value: session) { Label(action, systemImage: isStarted ? "arrow.right" : "play.fill") }
                        .buttonStyle(.primary)
                } else {
                    NavigationLink(value: session) { Label(action, systemImage: "arrow.right") }
                        .buttonStyle(.secondary)
                }
            }
        }
    }

    /// "Up next", "Tomorrow", "Thursday".
    private var eyebrow: String {
        if isToday { return isStarted ? "In progress" : "Up next today" }
        if coordinator.calendar.isDateInTomorrow(session.date) { return "Next up tomorrow" }
        return "Next up \(Format.weekday.string(from: session.date))"
    }

    private var action: String {
        guard isToday else { return "See the session" }
        switch session.modality {
        case .strength: return isStarted ? "Resume \(session.title.lowercased())" : "Start \(session.title.lowercased())"
        case .running: return "Start \(session.title.lowercased())"
        case .yoga: return "Start hot yoga"
        }
    }

    private var detail: String {
        switch session.modality {
        case .strength:
            let movements = session.orderedExercises.count
            return "\(session.subtitle), \(movements) movements, \(session.plannedSetCount) sets"
        case .running:
            return "A run on your watch logs itself from Apple Health."
        case .yoga:
            return "\(session.subtitle). Counts as recovery for the lifts around it."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.modality {
        case .strength:
            movements
        case .running:
            if let kind = session.runKind { runTarget(coordinator.runTarget(for: kind, asOf: session.date, in: context)) }
        case .yoga:
            if let forecast { weather(forecast) }
        }
    }

    /// The movements as a strip of thumbnails, the focus ones first in the order they are done.
    /// As many as fit the card's width, so the strip never pushes the page wider than the screen.
    private var movements: some View {
        let exercises = session.orderedExercises.compactMap(\.exercise)
        return ViewThatFits(in: .horizontal) {
            ForEach([5, 4, 3], id: \.self) { count in movementStrip(exercises, showing: count) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercises.map(\.name).formatted(.list(type: .and)))
    }

    private func movementStrip(_ exercises: [Exercise], showing count: Int) -> some View {
        let shown = exercises.prefix(count)
        return HStack(spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, exercise in
                MovementThumbnail(exercise: exercise, size: 52)
            }
            if exercises.count > shown.count {
                Text("+\(exercises.count - shown.count)")
                    .font(.numeralSmall)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 52, height: 52)
                    .background(Palette.raised, in: .rect(cornerRadius: 52 * 0.22, style: .continuous))
            }
        }
    }

    private func runTarget(_ target: RunTarget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let pace = target.pace {
                    Text("\(Format.pace(pace.fastest)) to \(Format.pace(pace.slowest))")
                        .font(.numeral)
                        .foregroundStyle(Palette.ink)
                    Text("/km").font(.body2).foregroundStyle(Palette.inkSecondary)
                } else {
                    Text("Run by feel").font(.rowTitle).foregroundStyle(Palette.ink)
                }
            }
            chipRow {
                Chip(symbol: "heart", text: target.heartRate.map { "Zone \(target.zone), \(Format.heartRate($0))" } ?? "Zone \(target.zone)", tint: Palette.rose)
                if let forecast { weatherChips(forecast) }
            }
        }
    }

    private func weather(_ forecast: DayForecast) -> some View {
        chipRow { weatherChips(forecast) }
    }

    /// Chips that scroll rather than squeeze, so a wet, windy day never truncates. The row runs
    /// out to just inside the card's border, where it clips, and rests in line with the content.
    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let bleed = Self.padding - 1.5 // the active border's width
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
        }
        .contentMargins(.horizontal, bleed, for: .scrollContent)
        .padding(.horizontal, -bleed)
    }

    @ViewBuilder
    private func weatherChips(_ forecast: DayForecast) -> some View {
        Chip(symbol: forecast.condition.symbolName, text: "\(Format.temperature(forecast.tempMaxC)) \(forecast.condition.displayName.lowercased())", tint: Palette.sky)
        if forecast.precipitationProbability >= 0.3 {
            Chip(symbol: "drop", text: "\(Format.percent(forecast.precipitationProbability)) rain", tint: Palette.sky)
        }
        if forecast.windKph >= 30 {
            Chip(symbol: "wind", text: "\(Int(forecast.windKph)) km/h", tint: Palette.sky)
        }
    }
}

/// A day with nothing left to do: rest, or everything already logged. A rest day can still be
/// changed to a session.
struct DayDoneCard: View {
    let date: Date
    let logged: [TrainingSession]

    var body: some View {
        Card(cornerRadius: 26, padding: 18) {
            HStack(spacing: 14) {
                SessionTile(symbol: logged.isEmpty ? "moon.zzz.fill" : "checkmark", tint: logged.isEmpty ? Palette.rest : Palette.sage, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(logged.isEmpty ? "Rest day" : "Done for today").font(.rowTitle).foregroundStyle(Palette.ink)
                    Text(message)
                        .font(.body2)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, alignment: .leading)
                if logged.isEmpty { RestDayMenu(date: date) }
            }
        }
    }

    private var message: String {
        guard !logged.isEmpty else { return "Walk, sleep, eat. Rest is when the week's work turns into fitness." }
        let titles = logged.map(\.title)
        let names = ([titles[0]] + titles.dropFirst().map { $0.lowercased() }).formatted(.list(type: .and))
        return "\(names) logged, \(Format.load(logged.map(\.load).reduce(0, +))) load."
    }
}
