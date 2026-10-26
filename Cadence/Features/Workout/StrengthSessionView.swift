import SwiftData
import SwiftUI
import TrainingEngine

/// The gym screen. One exercise expanded at a time, one big button to log the next set
/// with the prescription pre-filled, so a set takes two taps unless something changed.
struct StrengthSessionView: View {
    @Bindable var session: TrainingSession
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: PersistentIdentifier?
    @State private var confirmFinish = false

    var body: some View {
        ZStack {
            AtmosphereBackdrop(modality: .strength, intensity: session.status == .completed ? 0.5 : 0.9)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            ForEach(session.orderedExercises) { exercise in
                                ExerciseCard(
                                    exercise: exercise,
                                    isExpanded: expanded == exercise.persistentModelID,
                                    isEditable: session.status != .completed,
                                    onToggle: { toggle(exercise) },
                                    onSwap: { coordinator.swap(exercise, in: context) }
                                )
                            }
                        }
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle(session.title)
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
        .confirmationDialog("Finish session?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish with \(session.loggedSetCount) of \(session.plannedSetCount) sets") { finish() }
        } message: {
            Text("Unlogged sets are left out of progression. You can reopen the session later.")
        }
        .onAppear {
            if expanded == nil { expanded = session.orderedExercises.first { !$0.isComplete }?.persistentModelID }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.subtitle)
                    .font(.displaySmall)
                    .tracking(-1)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(Format.minutes(session.actualMinutes ?? session.plannedMinutes))
                    .font(.numeralSmall).foregroundStyle(Palette.inkSecondary)
            }
            ProgressView(value: Double(session.loggedSetCount), total: Double(max(1, session.plannedSetCount)))
                .tint(Palette.ember)
            HStack(spacing: 0) {
                Text("\(session.loggedSetCount) of \(session.plannedSetCount) sets")
                if let rir = session.loggedMeanRIR {
                    Text(", averaging \(String(format: "%.1f", rir)) in reserve")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var footer: some View {
        if session.status == .planned {
            Button {
                if session.loggedSetCount >= session.plannedSetCount { finish() } else { confirmFinish = true }
            } label: {
                Label("Finish session", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(session.loggedSetCount == 0)
        } else if session.status == .completed {
            GlassCard(tint: Palette.sage) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.sage).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Logged").font(.headline).foregroundStyle(Palette.ink)
                        Text(session.importKey != nil
                             ? "Imported from your previous log, \(Format.load(session.load)) load units. Reps in reserve were assumed to be 2."
                             : "Session RPE \(String(format: "%.1f", session.rpe ?? 0)), \(Format.load(session.load)) load units. Next week's loads are already adjusted.")
                            .font(.footnote).foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        }
    }

    private func toggle(_ exercise: PlannedExercise) {
        withAnimation(.snappy(duration: 0.3)) {
            expanded = expanded == exercise.persistentModelID ? nil : exercise.persistentModelID
        }
    }

    private func finish() {
        coordinator.complete(session, in: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct ExerciseCard: View {
    @Bindable var exercise: PlannedExercise
    let isExpanded: Bool
    let isEditable: Bool
    let onToggle: () -> Void
    let onSwap: () -> Void

    @Environment(\.modelContext) private var context
    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var rir: Int = 2
    @State private var showRationale = false

    private var increment: Double { exercise.exercise?.equipment.incrementKg ?? 2.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) { summary.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Collapses the exercise" : "Expands the exercise to log sets")
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    rationale
                    if !exercise.completedSets.isEmpty { loggedSets }
                    if isEditable, !exercise.isComplete { logger }
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassEffect(exercise.isFocus ? Glass.regular.tint(Palette.ember.opacity(0.16)) : .regular, in: .rect(cornerRadius: 24))
        .onAppear(perform: prime)
        .onChange(of: exercise.exerciseID) { prime() }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name).font(.headline).foregroundStyle(Palette.ink)
                    if exercise.isFocus {
                        Image(systemName: "scope").font(.caption.weight(.bold)).foregroundStyle(Palette.ember)
                            .accessibilityLabel("Focus movement")
                    }
                }
                Text("\(exercise.targetSets) × \(exercise.repLower) to \(exercise.repUpper) at \(exercise.targetRIR) in reserve")
                    .font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.weight(exercise.prescribedWeightKg))
                    .font(.numeralSmall)
                    .foregroundStyle(exercise.prescribedWeightKg == nil ? Palette.inkSecondary : Palette.ink)
                HStack(spacing: 3) {
                    ForEach(0..<exercise.targetSets, id: \.self) { index in
                        Capsule()
                            .fill(index < exercise.completedSets.count ? Palette.sage : Palette.hairline)
                            .frame(width: 14, height: 4)
                    }
                }
                .accessibilityLabel("\(exercise.completedSets.count) of \(exercise.targetSets) sets done")
            }
        }
    }

    private var rationale: some View {
        Text(exercise.rationale)
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var loggedSets: some View {
        VStack(spacing: 6) {
            ForEach(exercise.completedSets) { set in
                HStack {
                    Text("Set \(set.index + 1)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkSecondary).frame(width: 48, alignment: .leading)
                    Text("\(Format.kg(set.weightKg)) kg").font(.numeralSmall).foregroundStyle(Palette.ink)
                    Text("× \(set.reps)").font(.numeralSmall).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(set.rir) RIR").font(.footnote.weight(.semibold)).foregroundStyle(rirColor(set.rir))
                    if isEditable {
                        Button { remove(set) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkTertiary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove set \(set.index + 1)")
                    }
                }
            }
        }
    }

    private var logger: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                DialStepper(title: "kg", value: Binding(get: { weight }, set: { weight = max(0, $0) }), step: increment, format: Format.kg)
                DialStepper(title: "reps", value: Binding(get: { Double(reps) }, set: { reps = max(1, Int($0)) }), step: 1, format: { "\(Int($0))" })
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Reps in reserve").font(.label).foregroundStyle(Palette.inkSecondary)
                Picker("Reps in reserve", selection: $rir) {
                    ForEach(0...4, id: \.self) { value in Text(value == 4 ? "4+" : "\(value)").tag(value) }
                }
                .pickerStyle(.segmented)
            }
            Button(action: log) {
                Label("Log set \(exercise.completedSets.count + 1) of \(exercise.targetSets)", systemImage: "plus")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            HStack {
                Button("Swap movement", systemImage: "arrow.left.arrow.right", action: onSwap)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.inkSecondary)
                    .disabled(!exercise.completedSets.isEmpty)
                Spacer()
            }
        }
    }

    private func prime() {
        if let last = exercise.completedSets.last {
            weight = last.weightKg
            reps = last.reps
            rir = last.rir
        } else {
            weight = exercise.prescribedWeightKg ?? max(0, exercise.exercise?.startingWeightKg ?? 0)
            reps = exercise.repLower
            rir = exercise.targetRIR
        }
    }

    private func log() {
        let set = SetRecord(index: exercise.completedSets.count, weightKg: weight, reps: reps, rir: rir)
        set.completedAt = .now
        set.exercise = exercise
        exercise.sets.append(set)
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func remove(_ set: SetRecord) {
        context.delete(set)
        for (index, remaining) in exercise.completedSets.enumerated() { remaining.index = index }
        try? context.save()
        prime()
    }

    private func rirColor(_ rir: Int) -> Color {
        let diff = rir - exercise.targetRIR
        if diff >= 1 { return Palette.sky }
        if diff <= -1 { return Palette.amber }
        return Palette.sage
    }
}

/// A large tappable number with minus and plus either side. Repeats on long press.
struct DialStepper: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { value -= step }
            VStack(spacing: 0) {
                Text(format(value)).font(.numeral).foregroundStyle(Palette.ink).contentTransition(.numericText())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
            stepButton("plus") { value += step }
        }
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(format(value)) \(title)")
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(Palette.ink)
        .accessibilityLabel(symbol == "plus" ? "Increase \(title)" : "Decrease \(title)")
    }
}
