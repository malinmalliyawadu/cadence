import SwiftData
import SwiftUI
import TrainingEngine

/// The gym screen. One exercise expanded at a time, one big button to log the next set
/// with the prescription pre-filled, so a set takes two taps unless something changed.
struct StrengthSessionView: View {
    @Bindable var session: TrainingSession
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(HealthKitService.self) private var health
    @Environment(RestTimerService.self) private var rest
    @Environment(LiveWorkoutService.self) private var live
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Expanded exercise by position. Positions survive a regenerate; SwiftData IDs do not.
    @State private var expanded: Int?
    @State private var showFinish = false
    @FocusState private var focus: StepperField?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if !session.exercises.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Movements") {
                                    Text("\(session.loggedSetCount) of \(session.plannedSetCount) sets")
                                        .font(.label.monospacedDigit())
                                        .foregroundStyle(Palette.inkSecondary)
                                        .contentTransition(.numericText(value: Double(session.loggedSetCount)))
                                        .animation(Motion.settle, value: session.loggedSetCount)
                                }
                                ProgressBar(value: Double(session.loggedSetCount) / Double(max(1, session.plannedSetCount)), tint: session.status == .completed ? Palette.sage : Palette.accent)
                                    .padding(.bottom, 4)
                                ForEach(session.orderedExercises) { exercise in
                                    ExerciseCard(
                                        exercise: exercise,
                                        isExpanded: expanded == exercise.order,
                                        isEditable: session.status != .completed,
                                        focus: $focus,
                                        onToggle: { toggle(exercise, in: proxy) },
                                        onLogged: {
                                            startRest(after: exercise)
                                            revealLogger(in: proxy)
                                        }
                                    )
                                    .id(ExerciseCard.cardID(exercise.order))
                                }
                            }
                        }
                        footer
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if rest.isResting(in: session), let state = rest.state {
                RestCard(state: state, onAdjust: { rest.adjust(by: $0) }, onSkip: { rest.stop() })
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 8)
                    .transition(.rise(reduceMotion: reduceMotion))
                    .onAppear { rest.isOnScreen = true }
                    .onDisappear { rest.isOnScreen = false }
            }
        }
        .animation(Motion.reveal, value: rest.isResting(in: session))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if case .weight(let order) = focus {
                    Button("Next") { focus = .reps(order) }
                }
                Spacer()
                Button("Done") { focus = nil }.fontWeight(.semibold)
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.status == .planned {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Skip this session", systemImage: "forward.end", role: .destructive) {
                            rest.stop(for: session)
                            live.discard(session)
                            coordinator.skip(session, in: context)
                            dismiss()
                        }
                    } label: { Image(systemName: "ellipsis") }
                    // Toolbar controls stay white like the back button; violet marks what is active.
                    .tint(Palette.ink)
                }
            } else if session.status == .completed, !session.exercises.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reopen", systemImage: "arrow.uturn.backward") { reopen() }
                        .tint(Palette.ink)
                }
            }
        }
        .sheet(isPresented: $showFinish) {
            FinishSessionSheet(session: session) { finish(rpe: $0) }
        }
        .onAppear {
            if expanded == nil { expanded = session.orderedExercises.first { !$0.isComplete }?.order }
        }
        .onChange(of: session.focusRaw) { _, _ in
            expanded = 0
        }
        .onChange(of: session.loggedSetCount) { _, _ in
            live.progress(in: session)
            // Finishing a movement's last set moves straight on to the next one still to do.
            guard let current = session.orderedExercises.first(where: { $0.order == expanded }), current.isComplete,
                  let next = session.orderedExercises.first(where: { !$0.isComplete }) else { return }
            withAnimation(Motion.reveal) { expanded = next.order }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                DisplayText(text: session.subtitle)
                Text(description)
                    .font(.body2)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ChipFlow {
                Chip(symbol: "clock", text: Format.minutes(session.actualMinutes ?? session.plannedMinutes))
                if !session.exercises.isEmpty {
                    Chip(symbol: "dumbbell", text: "\(session.plannedSetCount) sets")
                }
                if live.isRecording(session) {
                    Chip(symbol: "heart.fill", text: Format.bpm(live.metrics.heartRate), tint: Palette.rose)
                    Chip(symbol: "flame", text: Format.kcal(live.metrics.activeKilocalories))
                } else {
                    if let heartRate = session.averageHeartRate {
                        Chip(symbol: "heart", text: Format.bpm(heartRate))
                    }
                    if let energy = session.activeKilocalories {
                        Chip(symbol: "flame", text: Format.kcal(energy))
                    }
                }
                if let rir = session.loggedMeanRIR {
                    Chip(symbol: "gauge.with.dots.needle.50percent", text: "\(String(format: "%.1f", rir)) RIR")
                }
                if session.status == .planned, session.loggedSetCount == 0 {
                    ChangeSessionButton(session: session)
                }
            }
        }
        .padding(.top, 8)
    }

    private var description: String {
        if session.exercises.isEmpty {
            return "Recorded outside Cadence, on your watch or in another app. It counts toward training load like any session logged here."
        }
        let base = "\(session.orderedExercises.count) movements. Rate reps in reserve on each movement's last set and next week's loads follow from it."
        return session.status == .completed ? "Logged. \(base)" : base
    }

    private var footer: some View {
        footerContent.animation(Motion.reveal, value: session.status)
    }

    @ViewBuilder
    private var footerContent: some View {
        if session.status == .planned {
            let allLogged = session.loggedSetCount >= session.plannedSetCount
            Group {
                if allLogged {
                    Button("Finish session", systemImage: "checkmark") { showFinish = true }
                        .buttonStyle(.primary)
                } else {
                    Button("Finish session", systemImage: "checkmark") { showFinish = true }
                        .buttonStyle(.secondary)
                }
            }
            .disabled(session.loggedSetCount == 0)
            .transition(.reveal)
        } else if session.status == .completed {
            Card {
                HStack(spacing: 14) {
                    TitleIcon(symbol: "checkmark", tint: Palette.sage)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Logged").font(.rowTitle).foregroundStyle(Palette.ink)
                        Text(loggedSummary)
                            .font(.body2).foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .transition(.reveal)
        }
    }

    private var loggedSummary: String {
        let effort = "Effort \(Format.kg(session.rpe ?? 0)), \(Format.load(session.load)) load units."
        if session.importKey != nil {
            return "Imported from your previous log, \(Format.load(session.load)) load units. Reps in reserve were assumed to be 2."
        }
        if session.loggedSetCount == 0 {
            if session.exercises.isEmpty {
                return "\(effort) No sets were logged, so next week's loads stay as they were."
            }
            return "\(effort) Completed from Apple Health with no sets logged, so next week's loads stay as they were. Reopen to log them."
        }
        return "\(effort) Next week's loads are already adjusted.\(session.healthWorkoutID != nil ? " In Apple Health." : "")"
    }

    /// Opens a movement and brings its card to the top, so it reads from its photo down whatever
    /// collapsed above it. Closing one leaves the page where it is.
    private func toggle(_ exercise: PlannedExercise, in proxy: ScrollViewProxy) {
        let opening = expanded != exercise.order
        withAnimation(Motion.reveal) {
            expanded = opening ? exercise.order : nil
            if opening { proxy.scrollTo(ExerciseCard.cardID(exercise.order), anchor: .top) }
        }
    }

    /// Rest before the next set to do, sized for its movement. Nothing left to do, no rest.
    private func startRest(after exercise: PlannedExercise) {
        guard let next = exercise.isComplete ? session.orderedExercises.first(where: { !$0.isComplete }) : exercise,
              let index = next.nextSetIndex else {
            rest.stop(for: session)
            return
        }
        let seconds = RestInterval.seconds(for: next.exercise?.role ?? .accessory, repRange: next.repRange)
        rest.start(seconds: seconds, before: next, set: index, in: session)
    }

    /// Brings the next set's logger into view once the card has moved on to it, its log button
    /// resting just above the rest card that has just appeared under it.
    private func revealLogger(in proxy: ScrollViewProxy) {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard let expanded else { return }
            withAnimation(Motion.reveal) { proxy.scrollTo(ExerciseCard.loggerID(expanded), anchor: .bottom) }
        }
    }

    private func finish(rpe: Double) {
        rest.stop(for: session)
        coordinator.complete(session, rpe: rpe, in: context)
        live.finish(session)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await health.record(session, in: context, coordinator: coordinator) }
    }

    private func reopen() {
        coordinator.reopen(session, in: context)
        Task { await health.withdraw(session, in: context) }
    }
}

/// One movement, led by its photo, which opens how it moves. Expanded, it lists every set: logged sets
/// with a check, upcoming sets with their own weight and reps and a pencil to change them. The next set
/// opens the logger under its row. Sets can be added or removed, and before anything is logged the
/// whole movement can switch scheme for a fresh session.
struct ExerciseCard: View {
    @Bindable var exercise: PlannedExercise
    let isExpanded: Bool
    let isEditable: Bool
    var focus: FocusState<StepperField?>.Binding
    let onToggle: () -> Void
    let onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var rir: Int = 2
    /// A later set being re-planned. `nil` means the editor sits on the next set to log.
    @State private var editing: Int?
    @State private var showSwap = false
    @State private var showMovement = false

    private var selected: Int? { editing ?? exercise.nextSetIndex }
    private var selectedIsNext: Bool { selected != nil && selected == exercise.nextSetIndex }
    /// RIR is asked once, on the last set: the closest to failure and the one the target refers to.
    private var asksRIR: Bool { selectedIsNext && selected == exercise.targetSets - 1 }
    private var increment: Double { exercise.exercise?.equipment.incrementKg ?? 2.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let movement = exercise.exercise {
                    Button { showMovement = true } label: { MovementThumbnail(exercise: movement, size: 56) }
                        .buttonStyle(.control)
                        .accessibilityLabel("How \(exercise.name) moves")
                        .accessibilityHint("Shows the photos, the muscles worked and your history")
                }
                Button(action: onToggle) { summary.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .accessibilityHint(isExpanded ? "Collapses the exercise" : "Expands the exercise to log sets")
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    rationale
                    if showsWarmUps { warmUpList }
                    setsHeader
                    setList
                    if isEditable { setControls }
                }
                .padding(.top, 14)
                .transition(.reveal)
            }
        }
        .padding(16)
        .surface(cornerRadius: 22)
        // Whatever opens inside the card stays inside it while it grows.
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .onAppear(perform: prime)
        .onChange(of: exercise.exerciseID) { editing = nil; prime() }
        .onChange(of: selected) { prime() }
        .onChange(of: exercise.prescribedWeightKg) { prime() }
        .sheet(isPresented: $showSwap) { SwapMovementSheet(exercise: exercise) }
        .sheet(isPresented: $showMovement) {
            if let movement = exercise.exercise { ExerciseDetailSheet(exercise: movement) }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.rowTitle).foregroundStyle(Palette.ink)
                Text("\(exercise.targetSets) × \(exercise.repLower) to \(exercise.repUpper), \(exercise.targetRIR) RIR")
                    .font(.body2).foregroundStyle(Palette.inkSecondary)
                    .accessibilityLabel("\(exercise.targetSets) sets of \(exercise.repLower) to \(exercise.repUpper), the last with \(exercise.targetRIR) reps in reserve")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(Format.weight(exercise.prescribedWeightKg))
                    .font(.numeralSmall)
                    .foregroundStyle(exercise.prescribedWeightKg == nil ? Palette.inkSecondary : Palette.ink)
                HStack(spacing: 3) {
                    ForEach(0..<exercise.targetSets, id: \.self) { index in
                        Capsule()
                            .fill(exercise.record(at: index)?.completedAt != nil ? Palette.accent : Color.white.opacity(0.12))
                            .frame(width: 12, height: 4)
                    }
                }
                .animation(Motion.settle, value: exercise.completedSets.count)
                .accessibilityLabel("\(exercise.completedSets.count) of \(exercise.targetSets) sets done")
            }
        }
    }

    private var rationale: some View {
        Text(exercise.rationale)
            .font(.body2)
            .foregroundStyle(Palette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Warm-ups lead the movement until its first working set is logged; after that they have done their job.
    private var showsWarmUps: Bool { isEditable && exercise.completedSets.isEmpty && !exercise.warmUps.isEmpty }

    private var warmUpList: some View {
        let ramp = exercise.warmUps
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Warm-up").font(.rowTitle).foregroundStyle(Palette.ink)
                Spacer()
                Text("Not counted").font(.label).foregroundStyle(Palette.inkTertiary)
            }
            .padding(.bottom, 6)
            ForEach(ramp.indices, id: \.self) { index in warmUpRow(ramp[index], at: index) }
        }
    }

    /// A warm-up set, on clear glass rather than filled so it reads lighter than a working set. Tapping
    /// ticks it and those before it off; tapping a ticked one undoes it and those after it.
    private func warmUpRow(_ set: WarmUpSet, at index: Int) -> some View {
        let done = index < exercise.warmUpsDone
        return Button {
            withAnimation(Motion.settle) { coordinator.setWarmUpsDone(done ? index : index + 1, for: exercise, in: context) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 0) {
                Group {
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.accent)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        Text("W").font(.label).foregroundStyle(Palette.inkTertiary)
                            .transition(.opacity)
                    }
                }
                .frame(width: 28, alignment: .leading)
                Text("\(Format.kg(set.weightKg)) kg").font(.numeralSmall)
                    .foregroundStyle(done ? Palette.ink : Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(set.reps) reps").font(.numeralSmall)
                    .foregroundStyle(done ? Palette.ink : Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The working rows' RIR column, so weights and reps line up across both lists.
                Color.clear.frame(width: 52, height: 1)
                Image(systemName: done ? "arrow.uturn.backward" : "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    // Centred where the working sets' glass buttons are.
                    .padding(.trailing, 18)
                    .frame(width: 58, height: 44, alignment: .trailing)
            }
            .padding(.leading, 14)
            .frame(minHeight: 48)
        }
        .buttonStyle(.option(cornerRadius: 14, isCurrent: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warm-up \(index + 1), \(Format.kg(set.weightKg)) kilograms for \(set.reps) reps")
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(done ? "Undoes this warm-up" : "Ticks this warm-up off")
    }

    private var setsHeader: some View {
        HStack {
            Text("Sets").font(.rowTitle).foregroundStyle(Palette.ink)
            Spacer()
            if isEditable, exercise.completedSets.isEmpty, let role = exercise.exercise?.role {
                Menu {
                    Section("Switch scheme for today") {
                        ForEach(SchemePreset.presets(for: role)) { preset in
                            Button {
                                editing = nil
                                withAnimation(Motion.reveal) { coordinator.apply(preset, to: exercise, in: context) }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                let label = "\(preset.name), \(preset.sets) × \(preset.reps.lowerBound) to \(preset.reps.upperBound)"
                                if matches(preset) { Label(label, systemImage: "checkmark") } else { Text(label) }
                            }
                        }
                    }
                } label: {
                    MenuChipLabel(text: "\(exercise.targetSets) × \(exercise.repLower) to \(exercise.repUpper)")
                }
                .accessibilityLabel("Scheme")
                .accessibilityValue("\(exercise.targetSets) sets of \(exercise.repLower) to \(exercise.repUpper)")
            }
        }
    }

    private var setList: some View {
        VStack(spacing: 8) {
            ForEach(0..<exercise.targetSets, id: \.self) { index in
                VStack(spacing: 10) {
                    setRow(index)
                    if isEditable, index == selected { editor(for: index).transition(.reveal) }
                }
            }
        }
    }

    @ViewBuilder
    private func setRow(_ index: Int) -> some View {
        let record = exercise.record(at: index)
        let logged = record?.completedAt != nil
        let isSelected = isEditable && index == selected
        let shown: (weightKg: Double, reps: Int) = isSelected ? (weight, reps) : exercise.target(at: index)

        HStack(spacing: 0) {
            Group {
                if logged {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.accent)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Text("\(index + 1)").font(.label.monospacedDigit()).foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
                        .transition(.opacity)
                }
            }
            .frame(width: 28, alignment: .leading)
            // Stepping the weight or reps rolls the row's figures to the new value.
            Text("\(Format.kg(shown.weightKg)) kg").font(.numeralSmall)
                .foregroundStyle(logged || isSelected ? Palette.ink : Palette.inkSecondary)
                .contentTransition(.numericText(value: shown.weightKg))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(shown.reps) reps").font(.numeralSmall)
                .foregroundStyle(logged || isSelected ? Palette.ink : Palette.inkSecondary)
                .contentTransition(.numericText(value: Double(shown.reps)))
                .frame(maxWidth: .infinity, alignment: .leading)
            // A fixed column so reps line up whether or not the set was rated.
            Text(record?.rir.map { "\($0) RIR" } ?? "")
                .font(.label.monospacedDigit())
                .foregroundStyle(record?.rir.map(rirColor) ?? Palette.inkTertiary)
                .frame(width: 52, alignment: .trailing)
            if isEditable {
                Button {
                    withAnimation(Motion.reveal) {
                        if logged, let record {
                            coordinator.unlogSet(record, in: context)
                            editing = nil
                        } else {
                            editing = index == exercise.nextSetIndex ? nil : index
                        }
                    }
                } label: {
                    // Inset from the edge as far as the set number is on the left, with the
                    // inset still part of the tap target.
                    GlassIcon(symbol: logged ? "arrow.uturn.backward" : "pencil", size: 34)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.trailing, 7)
                        .frame(width: 58, height: 44, alignment: .trailing)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(logged ? "Undo set \(index + 1)" : "Change set \(index + 1)")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, isEditable ? 0 : 14)
        .frame(minHeight: 48)
        // The set being logged is lit with a wash of the violet, not outlined.
        .background(isSelected ? Palette.accent.opacity(0.16) : Palette.raised.opacity(logged ? 0.7 : 0.4),
                    in: .rect(cornerRadius: 14, style: .continuous))
        .animation(Motion.settle, value: isSelected)
        .animation(Motion.settle, value: logged)
        .accessibilityElement(children: .combine)
    }

    static func loggerID(_ order: Int) -> String { "logger-\(order)" }
    static func cardID(_ order: Int) -> String { "movement-\(order)" }

    private func editor(for index: Int) -> some View {
        VStack(spacing: 12) {
            DialStepper(title: "kg", value: Binding(get: { weight }, set: { weight = max(0, $0) }), step: increment, format: Format.kg, keyboard: .decimalPad, focus: focus, field: .weight(exercise.order))
            DialStepper(title: "reps", value: Binding(get: { Double(reps) }, set: { reps = max(1, Int($0.rounded())) }), step: 1, format: { "\(Int($0))" }, keyboard: .numberPad, focus: focus, field: .reps(exercise.order))
            if asksRIR {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last set: how many more reps did you have?").font(.label).foregroundStyle(Palette.inkSecondary)
                    ChipPicker(title: "Reps in reserve", selection: $rir, options: (0...4).map { ($0, $0 == 4 ? "4+" : "\($0)") })
                }
                .transition(.opacity)
            }
            if selectedIsNext {
                Button { log(at: index) } label: {
                    Label("Log set \(index + 1) of \(exercise.targetSets)", systemImage: "plus")
                }
                .buttonStyle(.primary)
            } else {
                HStack(spacing: 10) {
                    Button("Cancel") { withAnimation(Motion.reveal) { editing = nil } }
                        .buttonStyle(.secondary)
                    Button("Save set \(index + 1)") { save(at: index) }
                        .buttonStyle(.primary)
                }
            }
        }
        .padding(.bottom, 4)
        .id(Self.loggerID(exercise.order))
    }

    /// Add set, Remove and Swap on one line; where Sora's wider words leave no room for all
    /// three, Swap keeps its glyph alone rather than every label being cut short.
    private var setControls: some View {
        ViewThatFits(in: .horizontal) {
            setControlsRow(swapLabelled: true)
            setControlsRow(swapLabelled: false)
        }
    }

    private func setControlsRow(swapLabelled: Bool) -> some View {
        let canRemove = exercise.targetSets > 1 && exercise.record(at: exercise.targetSets - 1)?.completedAt == nil
        return HStack(spacing: 8) {
            Button { withAnimation(Motion.reveal) { coordinator.addSet(to: exercise, in: context) } } label: {
                Chip(symbol: "plus", text: "Add set", tint: Palette.accent, glass: true)
            }
            .buttonStyle(.plain)
            .disabled(exercise.targetSets >= 10)
            Button {
                withAnimation(Motion.reveal) {
                    if editing == exercise.targetSets - 1 { editing = nil }
                    coordinator.removeLastSet(from: exercise, in: context)
                }
            } label: {
                Chip(symbol: "minus", text: "Remove", tint: Palette.inkSecondary, glass: true)
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .opacity(canRemove ? 1 : 0.4)
            Spacer(minLength: 0)
            if exercise.completedSets.isEmpty {
                Button { showSwap = true } label: {
                    if swapLabelled {
                        Chip(symbol: "arrow.left.arrow.right", text: "Swap", tint: Palette.inkSecondary, glass: true)
                    } else {
                        GlassIcon(symbol: "arrow.left.arrow.right", size: 40)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap movement")
            }
        }
    }

    private func matches(_ preset: SchemePreset) -> Bool {
        preset.sets == exercise.targetSets && preset.reps.lowerBound == exercise.repLower && preset.reps.upperBound == exercise.repUpper
    }

    private func prime() {
        let target = exercise.target(at: selected ?? 0)
        weight = target.weightKg
        reps = target.reps
        rir = exercise.targetRIR
    }

    private func log(at index: Int) {
        focus.wrappedValue = nil
        // The check lands, the editor moves down to the next set, and the progress fills, together.
        withAnimation(Motion.reveal) {
            coordinator.logSet(exercise, at: index, weightKg: weight, reps: reps, rir: asksRIR ? rir : nil, in: context)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SoundEffects.play(.setLogged)
        onLogged()
    }

    private func save(at index: Int) {
        focus.wrappedValue = nil
        withAnimation(Motion.reveal) {
            coordinator.planSet(exercise, at: index, weightKg: weight, reps: reps, in: context)
            editing = nil
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func rirColor(_ rir: Int) -> Color {
        let diff = rir - exercise.targetRIR
        if diff >= 1 { return Palette.sky }
        if diff <= -1 { return Palette.amber }
        return Palette.sage
    }
}

/// Which number field has the keyboard. Exercises are keyed by their position in the session.
enum StepperField: Hashable {
    case weight(Int)
    case reps(Int)
    case distance
}

/// A large number with minus and plus either side. The buttons repeat on long press for
/// small changes; tapping the number opens the keyboard, with the value selected so typing
/// replaces it.
struct DialStepper: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let format: (Double) -> String
    var keyboard: UIKeyboardType = .decimalPad
    var focus: FocusState<StepperField?>.Binding
    let field: StepperField

    @State private var text = ""
    @State private var selection: TextSelection?

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { value -= step }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // A text field sizes to its placeholder, so a hidden copy of the value sets the width.
                Text(text.isEmpty ? "0" : text)
                    .font(.numeral)
                    .padding(.horizontal, 3)
                    .hidden()
                    .overlay {
                        TextField(title, text: $text, selection: $selection)
                            .font(.numeral)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                            .keyboardType(keyboard)
                            .focused(focus, equals: field)
                            // The row's tap focuses the field, so UIKit never drops a caret
                            // over the selection and typing always replaces the value.
                            .allowsHitTesting(false)
                            .accessibilityLabel(title)
                    }
                Text(title).font(.body2).foregroundStyle(isFocused ? Palette.accent : Palette.inkTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
            .onTapGesture { focus.wrappedValue = field }
            stepButton("plus") { value += step }
        }
        .padding(8)
        // Typing into it lights it with the violet, as the set being logged is lit.
        .background(isFocused ? Palette.accent.opacity(0.16) : Palette.raised.opacity(0.7), in: .rect(cornerRadius: 18, style: .continuous))
        .animation(Motion.settle, value: isFocused)
        .onAppear { text = format(value) }
        .onChange(of: value) { _, new in
            if !isFocused { text = format(new) }
        }
        .onChange(of: text) { _, new in
            guard isFocused, let parsed = Double(new.replacingOccurrences(of: ",", with: ".")) else { return }
            value = parsed
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                Task { @MainActor in selection = TextSelection(range: text.startIndex..<text.endIndex) }
            } else {
                text = format(value)
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.settle) { action() }
            if isFocused { text = format(value) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            GlassIcon(symbol: symbol)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(symbol == "plus" ? "Increase \(title)" : "Decrease \(title)")
    }
}
