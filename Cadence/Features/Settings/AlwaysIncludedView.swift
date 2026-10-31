import SwiftData
import SwiftUI
import TrainingEngine

/// Movements added to every upper or lower session on top of the six the planner picks.
/// What is included sits at the top; the rest of the half is grouped by muscle below it.
struct AlwaysIncludedView: View {
    let half: BodyHalf
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Query private var profiles: [AthleteProfile]
    @State private var search = ""

    private var included: [Exercise] {
        (profiles.first?.alwaysIncluded(for: half) ?? []).compactMap(ExerciseLibrary.exercise(id:))
    }

    private var grouped: [(MuscleGroup, [Exercise])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let rest = ExerciseLibrary.exercises(for: half).filter { exercise in
            !included.contains(exercise) && (query.isEmpty || [exercise.name, exercise.primary.displayName, exercise.equipment.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        return MuscleGroup.allCases.filter { $0.half == half }.compactMap { group in
            let items = rest.filter { $0.primary == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                // Not lazy: a movement moves between sections under the same ID, and a lazy stack
                // would reuse its old row, unselected styling and all.
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Included")
                        .padding(.top, 8)
                    if included.isEmpty {
                        Text("Nothing yet. Tap a movement below to add it to every \(half.displayName.lowercased()) session.")
                            .font(.body2)
                            .foregroundStyle(Palette.inkSecondary)
                    } else {
                        ForEach(included) { row($0, isIncluded: true) }
                    }
                    ForEach(grouped, id: \.0) { group, items in
                        SectionHeader(title: group.displayName)
                            .padding(.top, 18)
                        ForEach(items) { row($0, isIncluded: false) }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
                .animation(Motion.settle, value: included)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Every \(half.displayName.lowercased()) session")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search movement, muscle or equipment")
    }

    private func row(_ exercise: Exercise, isIncluded: Bool) -> some View {
        Button { toggle(exercise, isIncluded: isIncluded) } label: {
            Group {
                HStack(alignment: .center, spacing: 12) {
                    MovementThumbnail(exercise: exercise, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.rowTitle).foregroundStyle(Palette.ink)
                        Text("\(exercise.primary.displayName), \(exercise.equipment.rawValue)")
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isIncluded ? Palette.accent : Palette.inkTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.option(isCurrent: isIncluded))
        .accessibilityLabel(exercise.name)
        .accessibilityValue(isIncluded ? "Included" : "Not included")
        .accessibilityHint(isIncluded ? "Removes it from every \(half.displayName.lowercased()) session" : "Adds it to every \(half.displayName.lowercased()) session")
    }

    private func toggle(_ exercise: Exercise, isIncluded: Bool) {
        var ids = included.map(\.id)
        if isIncluded { ids.removeAll { $0 == exercise.id } } else { ids.append(exercise.id) }
        coordinator.setAlwaysIncluded(ids, for: half, in: context)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
