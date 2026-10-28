import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// First launch, or a week nothing has been planned for.
struct EmptyPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(HealthKitService.self) private var health
    @Query private var sessions: [TrainingSession]
    @State private var showImporter = false
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            OrbitMark(drawsIn: true)
                .frame(maxWidth: 168)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                DisplayText(text: "This week is unwritten.")
                Text(sessions.isEmpty
                     ? "Cadence builds your week around four lifts, your runs and hot yoga, then sizes every set from reps in reserve.\(health.isEnabled ? "" : " Connect Apple Health in settings so runs and classes log themselves.")"
                     : "Plan the week and the lifts pick up exactly where your last session left off.")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await coordinator.planWeek(in: context) }
            } label: {
                Label(coordinator.phase == .planning ? "Planning" : "Plan my week", systemImage: "sparkles")
            }
            .buttonStyle(.primary)
            .disabled(coordinator.phase == .planning || importing)
            if sessions.isEmpty {
                Button {
                    showImporter = true
                } label: {
                    Label(importing ? "Importing" : "Import a workout export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.secondary)
                .disabled(importing)
            }
            if let importMessage {
                Text(importMessage).font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
            if let note = coordinator.forecastError {
                Label(note, systemImage: "cloud.slash").font(.footnote).foregroundStyle(Palette.inkTertiary)
            }
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 24)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            importing = true
            Task {
                importMessage = await ImportService.importPicked(result, replacingExisting: false, in: context, coordinator: coordinator)
                importing = false
            }
        }
    }
}
