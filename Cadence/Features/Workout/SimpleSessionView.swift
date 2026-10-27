import SwiftData
import SwiftUI
import TrainingEngine

/// Runs and hot yoga: duration, effort and (for runs) distance. Three controls, one button.
struct SimpleSessionView: View {
    @Bindable var session: TrainingSession
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ForecastDay.date) private var forecasts: [ForecastDay]
    @State private var minutes: Double = 0
    @State private var rpe: Double = 5
    @State private var distance: Double = 0
    @FocusState private var focus: StepperField?

    private var forecast: DayForecast? { forecasts.first { coordinator.calendar.isDate($0.date, inSameDayAs: session.date) }?.forecast }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        DisplayText(text: session.title)
                        Text(guidance).font(.body2).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    if session.modality == .running, let kind = session.runKind {
                        targetCard(coordinator.runTarget(for: kind, asOf: session.date, in: context))
                    }

                    dial
                    chips

                    if session.status == .completed {
                        completedCard
                    } else {
                        if session.modality == .running {
                            Card { DialStepper(title: "km", value: Binding(get: { distance }, set: { distance = max(0, $0) }), step: 0.5, format: { String(format: "%.1f", $0) }, focus: $focus, field: .distance) }
                        }
                        effort
                        Button {
                            coordinator.complete(session, minutes: minutes, rpe: rpe, distanceKm: session.modality == .running ? distance : nil, in: context)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Label("Log \(session.modality == .running ? "run" : "class")", systemImage: "checkmark")
                        }
                        .buttonStyle(.primary)
                    }

                    if session.modality == .running, let forecast { weatherCard(forecast) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(Format.dayMonth.string(from: session.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }.fontWeight(.semibold)
            }
            if session.status == .planned {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Skip this session", systemImage: "forward.end", role: .destructive) {
                            coordinator.skip(session, in: context)
                            dismiss()
                        }
                    } label: { Image(systemName: "ellipsis") }
                    // Toolbar controls stay white like the back button; blue marks what is active.
                    .tint(Palette.ink)
                }
            } else if session.status == .completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reopen", systemImage: "arrow.uturn.backward") { coordinator.reopen(session, in: context) }
                        .tint(Palette.ink)
                }
            }
        }
        .onChange(of: session.runKindRaw) { _, _ in
            minutes = session.plannedMinutes
            rpe = session.runKind?.defaultRPE ?? rpe
        }
        .onAppear {
            minutes = session.actualMinutes ?? session.plannedMinutes
            rpe = session.rpe ?? session.runKind?.defaultRPE ?? 5
            distance = session.distanceKm ?? (session.plannedMinutes / 6.2 * 2).rounded() / 2
        }
    }

    /// Minutes against the plan. The ring fills as the duration reaches what was planned;
    /// minus and plus either side set what you actually did.
    private var dial: some View {
        let shown = session.status == .completed ? (session.actualMinutes ?? session.plannedMinutes) : minutes
        let isDone = session.status == .completed
        return HStack(spacing: 0) {
            if !isDone { ringButton("minus") { minutes = max(0, minutes - 5) } }
            ProgressRing(progress: shown / max(1, session.plannedMinutes), tint: isDone ? Palette.sage : Palette.accent) {
                VStack(spacing: 2) {
                    Image(systemName: isDone ? "checkmark" : session.modality.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.1), in: .circle)
                        .padding(.bottom, 6)
                    Text("\(Int(shown))")
                        .font(.system(size: 64, weight: .bold).monospacedDigit())
                        .tracking(-1.5)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text("Minutes")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(shown)) of \(Int(session.plannedMinutes)) planned minutes")
            .accessibilityAdjustableAction { direction in
                guard !isDone else { return }
                switch direction {
                case .increment: minutes += 5
                case .decrement: minutes = max(0, minutes - 5)
                @unknown default: break
                }
            }
            if !isDone { ringButton("plus") { minutes += 5 } }
        }
        .frame(maxWidth: .infinity)
    }

    private func ringButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.raised, in: .circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityHidden(true)
    }

    /// The run's targets, the most important thing on the screen: a pace band to hold and the
    /// heart-rate zone that confirms it. Once logged, the average pace and heart rate sit against them.
    private func targetCard(_ target: RunTarget) -> some View {
        let done = session.status == .completed
        let zones = coordinator.profile(in: context).heartRateZones
        return Card(isActive: !done) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(done ? "Average pace" : target.kind == .quality ? "Threshold pace, 20 minute block" : "Target pace")
                        .font(.label).foregroundStyle(Palette.inkSecondary)
                    if done, let pace = session.actualPace {
                        paceLine(Format.pace(pace))
                        if let goal = target.pace {
                            Text("Target \(Format.pace(goal))").font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                        }
                    } else if let pace = target.pace {
                        paceLine("\(Format.pace(pace.fastest)) to \(Format.pace(pace.slowest))")
                        if let easy = target.easyPace {
                            Text("Warm up and cool down at \(Format.pace(easy))").font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                        }
                    } else {
                        Text("Run by feel. There are no runs in the last eight weeks to set a pace from.")
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack(spacing: 12) {
                    IconDisc(symbol: "heart", tint: Palette.rose)
                    VStack(alignment: .leading, spacing: 2) {
                        if done, let average = session.averageHeartRate {
                            Text("Average \(Int(average)) bpm").font(.rowTitle.monospacedDigit()).foregroundStyle(Palette.ink)
                            Text(zones.map { "Zone \(zone(of: Int(average), in: $0)), target zone \(target.zone)" } ?? "Target zone \(target.zone)")
                                .font(.body2).foregroundStyle(Palette.inkSecondary)
                        } else {
                            Text("Zone \(target.zone)").font(.rowTitle).foregroundStyle(Palette.ink)
                            Text(target.heartRate.map(Format.heartRate) ?? "Set your max heart rate in settings to see beats per minute")
                                .font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func paceLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text).font(.system(size: 40, weight: .bold).monospacedDigit()).tracking(-0.8).foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("/km").font(.title2).foregroundStyle(Palette.inkSecondary)
        }
    }

    private func zone(of heartRate: Int, in zones: HeartRateZones) -> Int {
        (1...5).last { heartRate >= zones.range(zone: $0).lowerBound } ?? 1
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(symbol: "clock", text: "\(Int(session.plannedMinutes)) min planned")
                Chip(symbol: "flame", text: "RPE \(Int((session.status == .completed ? session.rpe ?? rpe : rpe).rounded()))")
                if session.modality == .running {
                    Chip(symbol: "point.topleft.down.to.point.bottomright.curvepath", text: String(format: "%.1f km", session.distanceKm ?? distance))
                }
                if session.status == .planned {
                    ChangeSessionMenu(session: session)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var effort: some View {
        EffortCard(title: "How hard was it?", rpe: $rpe)
    }

    private var guidance: String {
        switch session.modality {
        case .running:
            switch session.runKind {
            case .easy: "\(Int(session.plannedMinutes)) minutes you could hold a conversation through. Effort 3 to 4."
            case .long: "\(Int(session.plannedMinutes)) minutes, steady. Start slower than feels right; finish strong."
            case .quality: "\(Int(session.plannedMinutes)) minutes with the hard part in the middle: 10 easy, 20 at threshold, 10 easy."
            case nil: "\(Int(session.plannedMinutes)) minutes."
            }
        case .yoga:
            "\(Int(session.plannedMinutes)) minute hot class. Hydrate before, not during. Counts as recovery for the lifts around it."
        case .strength:
            ""
        }
    }

    private func weatherCard(_ forecast: DayForecast) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: forecast.condition.symbolName)
                    .symbolRenderingMode(.multicolor).font(.system(size: 30))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(forecast.condition.displayName), \(Format.temperature(forecast.tempMinC)) to \(Format.temperature(forecast.tempMaxC))")
                        .font(.rowTitle).foregroundStyle(Palette.ink)
                    Text("\(Format.percent(forecast.precipitationProbability)) chance of rain, wind to \(Int(forecast.windKph)) km/h. \(forecast.isGoodRunningDay ? "Good running weather." : "Not the best day; this was still the best slot this week.")")
                        .font(.body2).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var completedCard: some View {
        Card {
            HStack(spacing: 14) {
                IconDisc(symbol: "checkmark", tint: Palette.sage)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Logged").font(.rowTitle).foregroundStyle(Palette.ink)
                    Text("\(Format.minutes(session.actualMinutes ?? session.plannedMinutes))\(session.distanceKm.map { String(format: ", %.1f km", $0) } ?? ""), RPE \(Int((session.rpe ?? 0).rounded())), \(Format.load(session.load)) load units.\(session.healthWorkoutID != nil ? " From Apple Health." : session.importKey != nil ? " Imported; effort estimated from the run type." : "")")
                        .font(.body2).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
