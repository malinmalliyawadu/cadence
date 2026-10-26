import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// First launch, or a week nothing has been planned for. Two doors: plan now, or look around with sample history.
struct EmptyPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query private var sessions: [TrainingSession]
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                DisplayText(text: "This week is unwritten.")
                Text(sessions.isEmpty
                     ? "Cadence builds your week around four lifts, your runs and hot yoga, then sizes every set from reps in reserve."
                     : "Plan the week and the lifts pick up exactly where your last session left off.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
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

                if sessions.isEmpty {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import a workout export", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    Button {
                        SampleData.seed(in: context, coordinator: coordinator)
                        Task { await coordinator.planWeek(in: context) }
                    } label: {
                        Label("Try with eight weeks of sample history", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                }
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
            switch result {
            case .success(let url):
                do {
                    let summary = try ImportService.importExport(at: url, replacingExisting: true, in: context, coordinator: coordinator)
                    importMessage = summary.message
                    Task { await coordinator.planWeek(in: context) }
                } catch {
                    importMessage = "Could not import: \(error.localizedDescription)"
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
    }
}
