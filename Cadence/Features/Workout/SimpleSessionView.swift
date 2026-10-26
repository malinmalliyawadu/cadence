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

    private var forecast: DayForecast? { forecasts.first { coordinator.calendar.isDate($0.date, inSameDayAs: session.date) }?.forecast }

    var body: some View {
        ZStack {
            AtmosphereBackdrop(modality: session.modality, forecast: forecast, intensity: session.status == .completed ? 0.5 : 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        DisplayText(text: session.title, size: 44)
                        Text(guidance).font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if session.status == .planned {
                            ChangeSessionMenu(session: session).padding(.top, 4)
                        }
                    }
                    .padding(.top, 8)

                    if session.modality == .running, let forecast { weatherCard(forecast) }

                    if session.status == .completed {
                        completedCard
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 18) {
                                DialStepper(title: "minutes", value: $minutes, step: 5, format: { "\(Int($0))" })
                                if session.modality == .running {
                                    DialStepper(title: "km", value: $distance, step: 0.5, format: { String(format: "%.1f", $0) })
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("How hard was it?").font(.label).foregroundStyle(Palette.inkSecondary)
                                        Spacer()
                                        Text("RPE \(String(format: "%.0f", rpe)), \(rpeWord)").font(.numeralSmall).foregroundStyle(Palette.ink)
                                    }
                                    Slider(value: $rpe, in: 1...10, step: 1)
                                        .tint(session.modality.tint)
                                        .accessibilityLabel("Rating of perceived exertion")
                                }
                                Button {
                                    coordinator.complete(session, minutes: minutes, rpe: rpe, distanceKm: session.modality == .running ? distance : nil, in: context)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } label: {
                                    Label("Log \(session.modality == .running ? "run" : "class")", systemImage: "checkmark")
                                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle(Format.dayMonth.string(from: session.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.status == .planned {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Skip this session", systemImage: "forward.end", role: .destructive) {
                            coordinator.skip(session, in: context)
                            dismiss()
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            } else if session.status == .completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reopen", systemImage: "arrow.uturn.backward") { coordinator.reopen(session, in: context) }
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

    private var rpeWord: String {
        switch rpe {
        case ..<3: "very easy"
        case ..<5: "easy"
        case ..<7: "moderate"
        case ..<9: "hard"
        default: "all out"
        }
    }

    private func weatherCard(_ forecast: DayForecast) -> some View {
        GlassCard(tint: Palette.sky) {
            HStack(spacing: 14) {
                Image(systemName: forecast.condition.symbolName)
                    .symbolRenderingMode(.multicolor).font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(forecast.condition.displayName), \(Format.temperature(forecast.tempMinC)) to \(Format.temperature(forecast.tempMaxC))")
                        .font(.headline).foregroundStyle(Palette.ink)
                    Text("\(Format.percent(forecast.precipitationProbability)) chance of rain, wind to \(Int(forecast.windKph)) km/h. \(forecast.isGoodRunningDay ? "Good running weather." : "Not the best day; this was still the best slot this week.")")
                        .font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private var completedCard: some View {
        GlassCard(tint: Palette.sage) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.sage).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logged").font(.headline).foregroundStyle(Palette.ink)
                    Text("\(Format.minutes(session.actualMinutes ?? session.plannedMinutes))\(session.distanceKm.map { String(format: ", %.1f km", $0) } ?? ""), RPE \(Int((session.rpe ?? 0).rounded())), \(Format.load(session.load)) load units.\(session.healthWorkoutID != nil ? " From Apple Health." : session.importKey != nil ? " Imported; effort estimated from the run type." : "")")
                        .font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }
}
