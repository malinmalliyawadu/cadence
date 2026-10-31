import SwiftData
import SwiftUI
import TrainingEngine

/// Pick what replaces a movement. Ranked by fit for the slot and the session's focus, with a
/// search across name, muscle and equipment for when you know exactly what is free.
struct SwapMovementSheet: View {
    let exercise: PlannedExercise
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var options: [SwapOption] = []
    @State private var loads: [String: Double?] = [:]
    @State private var search = ""

    private static let bestMatchCount = 5

    private var filtered: [SwapOption] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return options }
        return options.filter { option in
            [option.exercise.name, option.exercise.primary.displayName, option.exercise.equipment.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if search.isEmpty {
                            section("Best matches", Array(options.prefix(Self.bestMatchCount)))
                            section("Everything else", Array(options.dropFirst(Self.bestMatchCount)))
                        } else if filtered.isEmpty {
                            Text("No movement matches “\(search)”. Equipment you have turned off in settings is left out.")
                                .font(.body2)
                                .foregroundStyle(Palette.inkSecondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(filtered) { row($0) }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Swap \(exercise.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search movement, muscle or equipment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationBackground(Palette.canvas)
        .task { load() }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [SwapOption]) -> some View {
        if !items.isEmpty {
            SectionHeader(title: title)
                .padding(.top, title == "Best matches" ? 8 : 18)
            ForEach(items) { row($0) }
        }
    }

    private func row(_ option: SwapOption) -> some View {
        Button { swap(to: option) } label: {
            Group {
                HStack(alignment: .center, spacing: 12) {
                    MovementThumbnail(exercise: option.exercise)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.exercise.name).font(.rowTitle).foregroundStyle(Palette.ink)
                        Text("\(option.exercise.primary.displayName), \(option.exercise.equipment.rawValue)")
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                        if !option.reason.isEmpty {
                            Text(option.reason).font(.label).foregroundStyle(Palette.accent)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Format.weight(loads[option.id] ?? nil))
                        .font(.numeralSmall)
                        .foregroundStyle((loads[option.id] ?? nil) == nil ? Palette.inkTertiary : Palette.ink)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.option)
        .accessibilityHint("Replaces \(exercise.name) in this session")
        // Press and hold to see how a movement moves before committing to it.
        .contextMenu {
            Button("Swap to \(option.exercise.name)", systemImage: "arrow.left.arrow.right") { swap(to: option) }
        } preview: {
            VStack(alignment: .leading, spacing: 16) {
                Text(option.exercise.name).font(.rowTitle).foregroundStyle(Palette.ink)
                MovementVisual(exercise: option.exercise)
            }
            .padding(20)
            .frame(width: 360)
            .background(Palette.surface)
        }
    }

    private func swap(to option: SwapOption) {
        coordinator.swap(exercise, to: option.exercise, in: context)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }

    private func load() {
        options = coordinator.swapOptions(for: exercise, in: context)
        let history = coordinator.history(in: context)
        let bodyweight = coordinator.profile(in: context).bodyweightKg
        let readiness = coordinator.readiness(for: exercise, in: context)
        loads = Dictionary(uniqueKeysWithValues: options.map { option in
            (option.id, coordinator.prescription(for: option.exercise, in: exercise, history: history, readiness: readiness, bodyweightKg: bodyweight).weightKg)
        })
    }
}
