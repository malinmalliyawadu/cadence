import SwiftData
import SwiftUI

/// First launch, or a week nothing has been planned for.
struct EmptyPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query private var sessions: [TrainingSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                DisplayText(text: "This week is unwritten.")
                Text(sessions.isEmpty
                     ? "Cadence builds your week around four lifts, your runs and hot yoga, then sizes every set from reps in reserve. Connect Apple Health in settings so runs and classes log themselves."
                     : "Plan the week and the lifts pick up exactly where your last session left off.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await coordinator.planWeek(in: context) }
            } label: {
                Label(coordinator.phase == .planning ? "Planning" : "Plan my week", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(coordinator.phase == .planning)
            if let note = coordinator.forecastError {
                Label(note, systemImage: "cloud.slash").font(.footnote).foregroundStyle(Palette.inkTertiary)
            }
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 24)
    }
}
