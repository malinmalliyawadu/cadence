import Charts
import SwiftData
import SwiftUI
import TrainingEngine

struct LibraryView: View {
    @State private var search = ""
    @State private var half: BodyHalf = .upper

    private var exercises: [Exercise] {
        ExerciseLibrary.exercises(for: half).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var grouped: [(MuscleGroup, [Exercise])] {
        MuscleGroup.allCases.filter { $0.half == half }.compactMap { group in
            let items = exercises.filter { $0.primary == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ChipPicker(title: "Half", selection: $half, options: BodyHalf.allCases.map { ($0, $0.displayName) })
                        ForEach(grouped, id: \.0) { group, items in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: group.displayName)
                                VStack(spacing: 8) {
                                    ForEach(items) { exercise in
                                        NavigationLink(value: exercise) { ExerciseLibraryRow(exercise: exercise) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "Movement")
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
        }
    }
}

struct ExerciseLibraryRow: View {
    let exercise: Exercise

    var body: some View {
        Card(cornerRadius: 18, padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name).font(.rowTitle).foregroundStyle(Palette.ink)
                    Text("\(exercise.role.rawValue.capitalized), \(exercise.equipment.rawValue)\(exercise.secondary.isEmpty ? "" : ". Also " + exercise.secondary.map { $0.displayName.lowercased() }.joined(separator: ", "))")
                        .font(.body2).foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

/// The movement screen on its own, for checking a movement from inside a session.
struct ExerciseDetailSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exercise: exercise)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationBackground(Palette.canvas)
    }
}

/// One movement's story: how it moves, estimated one-rep max over time, and every logged session.
struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(PlanCoordinator.self) private var coordinator
    @Query(sort: \TrainingSession.date) private var sessions: [TrainingSession]

    private var entries: [ExerciseHistoryEntry] {
        sessions.filter { $0.status == .completed }
            .flatMap { $0.exercises.filter { $0.exerciseID == exercise.id }.compactMap(\.historyEntry) }
            .sorted { $0.date < $1.date }
    }
    private var points: [(date: Date, e1rm: Double)] { entries.compactMap { entry in entry.sessionOneRepMax.map { (entry.date, $0) } } }
    private var next: ProgressionResult {
        Progression.nextLoad(for: exercise, history: entries, repRange: WorkoutGenerator.openerScheme.reps, targetRIR: WorkoutGenerator.openerScheme.rir)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        DisplayText(text: exercise.name)
                        Text("\(exercise.primary.displayName) \(exercise.role.rawValue), \(exercise.equipment.rawValue). Loads move in \(Format.kg(exercise.equipment.incrementKg))\u{00A0}kg steps.")
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    Card { MovementVisual(exercise: exercise) }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 10) {
                                TitleIcon(symbol: "arrow.up.right", tint: Palette.accent)
                                Text("Next time").font(.rowTitle).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(Format.weight(next.weightKg)).font(.numeral).foregroundStyle(Palette.ink)
                            }
                            Text(next.rationale).font(.body2).foregroundStyle(Palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if points.count >= 2 { trendChart }

                    if entries.isEmpty {
                        Text("No sessions logged on this movement yet.").font(.body2).foregroundStyle(Palette.inkTertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "History")
                            ForEach(entries.reversed(), id: \.date) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(Format.monthDay.string(from: entry.date)).font(.label).foregroundStyle(Palette.inkSecondary).frame(width: 52, alignment: .leading)
                                    Text(entry.workingSets.map { "\(Format.kg($0.weightKg))×\($0.reps)" }.joined(separator: "  "))
                                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Palette.ink)
                                    Spacer(minLength: 8)
                                    Text("e1RM \(Format.kg(entry.sessionOneRepMax ?? 0))").font(.label.monospacedDigit()).foregroundStyle(Palette.inkTertiary)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 48)
                                .background(Palette.surface, in: .rect(cornerRadius: 14, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(exercise.primary.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TitleIcon(symbol: "chart.line.uptrend.xyaxis")
                Text("Estimated one-rep max").font(.rowTitle).foregroundStyle(Palette.ink)
            }
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                    .foregroundStyle(Palette.accent).lineStyle(.init(lineWidth: 2.5)).interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                    .foregroundStyle(Palette.accent).symbolSize(40)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Palette.inkTertiary) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel().foregroundStyle(Palette.inkTertiary) } }
            .frame(height: 160)
        }
        .padding(16)
        .surface()
    }
}
