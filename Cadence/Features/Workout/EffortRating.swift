import SwiftUI

/// The 1 to 10 effort question, on Apple's Workout Effort Score scale so a rating means the same
/// here and in Fitness.
struct EffortCard: View {
    let title: String
    @Binding var rpe: Double

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(.rowTitle).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(Int(rpe)), \(Self.word(for: rpe))").font(.numeralSmall).foregroundStyle(Palette.accent)
                        .contentTransition(.numericText(value: rpe))
                        .animation(Motion.settle, value: rpe)
                }
                Slider(value: $rpe, in: 1...10, step: 1)
                    .sensoryFeedback(.selection, trigger: rpe)
                    .tint(Palette.accent)
                    .accessibilityLabel("Effort")
                    .accessibilityValue("\(Int(rpe)), \(Self.word(for: rpe))")
            }
        }
    }

    /// Fitness's bands: easy, moderate, hard, all out.
    static func word(for rpe: Double) -> String {
        switch rpe {
        case ..<4: "easy"
        case ..<7: "moderate"
        case ..<9: "hard"
        default: "all out"
        }
    }
}

/// Asked when a strength session finishes. The rating sets the session's training load and goes
/// to Apple Health as the workout's effort; reps in reserve still drive next week's loads.
struct FinishSessionSheet: View {
    let session: TrainingSession
    let onFinish: (Double) -> Void
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(HealthKitService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double = 5
    @State private var height: CGFloat = 400

    private var allLogged: Bool { session.loggedSetCount >= session.plannedSetCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How hard was the session?").font(.title2).foregroundStyle(Palette.ink)
                Text(explanation)
                    .font(.body2).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            EffortCard(title: "Effort", rpe: $rpe)
            Button(allLogged ? "Finish session" : "Finish with \(session.loggedSetCount) of \(session.plannedSetCount) sets", systemImage: "checkmark") {
                onFinish(rpe)
                dismiss()
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
        .onAppear {
            rpe = min(10, max(1, (session.rpe ?? coordinator.suggestedEffort(for: session)).rounded()))
        }
    }

    private var explanation: String {
        var text = "1 is barely working, 10 is all out. It sets this session's training load\(health.isEnabled ? " and goes to Apple Health as the workout's effort" : "")."
        if !allLogged { text += " Unlogged sets are left out of progression." }
        return text
    }
}
