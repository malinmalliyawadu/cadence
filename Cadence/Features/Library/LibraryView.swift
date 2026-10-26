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
                AtmosphereBackdrop(modality: .strength, intensity: 0.45)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("Half", selection: $half) {
                            ForEach(BodyHalf.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        ForEach(grouped, id: \.0) { group, items in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.displayName).font(.headline).foregroundStyle(Palette.ink)
                                GlassEffectContainer(spacing: 8) {
                                    VStack(spacing: 8) {
                                        ForEach(items) { exercise in
                                            NavigationLink(value: exercise) { ExerciseLibraryRow(exercise: exercise) }
                                                .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
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
        GlassRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline).foregroundStyle(Palette.ink)
                    Text("\(exercise.role.rawValue.capitalized), \(exercise.equipment.rawValue)\(exercise.secondary.isEmpty ? "" : ". Also " + exercise.secondary.map { $0.displayName.lowercased() }.joined(separator: ", "))")
                        .font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

/// One movement's story: estimated one-rep max over time, and every logged session.
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
            AtmosphereBackdrop(modality: .strength, intensity: 0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        DisplayText(text: exercise.name, size: 40)
                        Text("\(exercise.primary.displayName) \(exercise.role.rawValue), \(exercise.equipment.rawValue). Loads move in \(Format.kg(exercise.equipment.incrementKg)) kg steps.")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    GlassCard(tint: Palette.ember) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Next time").font(.headline).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(Format.weight(next.weightKg)).font(.numeral).foregroundStyle(Palette.ink)
                            }
                            Text(next.rationale).font(.footnote).foregroundStyle(Palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if points.count >= 2 { trendChart }

                    if entries.isEmpty {
                        Text("No sessions logged on this movement yet.").font(.footnote).foregroundStyle(Palette.inkTertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("History").font(.headline).foregroundStyle(Palette.ink)
                            ForEach(entries.reversed(), id: \.date) { entry in
                                HStack(alignment: .top) {
                                    Text(Format.monthDay.string(from: entry.date)).font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkSecondary).frame(width: 56, alignment: .leading)
                                    Text(entry.workingSets.map { "\(Format.kg($0.weightKg))×\($0.reps)@\($0.rir)" }.joined(separator: "  "))
                                        .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text("e1RM \(Format.kg(entry.sessionOneRepMax ?? 0))").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkTertiary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle(exercise.primary.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Estimated one-rep max").font(.headline).foregroundStyle(Palette.ink)
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                    .foregroundStyle(Palette.ember).lineStyle(.init(lineWidth: 2.5)).interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                    .foregroundStyle(Palette.ember).symbolSize(40)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Palette.inkTertiary) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel().foregroundStyle(Palette.inkTertiary) } }
            .frame(height: 160)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
