import SwiftData
import SwiftUI
import TrainingEngine

/// The "Change" chip on a session: opens a sheet with everything the athlete can change before
/// starting it. Hidden once something has been logged, keeping its place so the row never shifts.
struct ChangeSessionButton: View {
    let session: TrainingSession
    @State private var isPresented = false

    var isAvailable: Bool { session.status == .planned && session.loggedSetCount == 0 }

    var body: some View {
        Button { isPresented = true } label: { ChangeChip() }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : 0)
            .accessibilityHidden(!isAvailable)
            .accessibilityHint("Changes the focus, the type or the day")
            .sheet(isPresented: $isPresented) { ChangeSessionSheet(session: session) }
    }
}

/// The "Change" chip on a rest day from today on: opens a sheet to train instead, or to bring a
/// session over from another day.
struct RestDayButton: View {
    let date: Date
    @Environment(PlanCoordinator.self) private var coordinator
    @State private var isPresented = false

    var body: some View {
        if date >= coordinator.calendar.startOfDay(for: .now) {
            Button { isPresented = true } label: { ChangeChip() }
                .buttonStyle(.plain)
                .accessibilityHint("Adds a session to this day or moves one here")
                .sheet(isPresented: $isPresented) { RestDaySheet(date: date) }
        }
    }
}

private struct ChangeChip: View {
    var body: some View {
        Chip(symbol: "arrow.triangle.swap", text: "Change", tint: Palette.accent, glass: true)
    }
}

// MARK: A session

/// Everything about a planned session that can change before it starts, laid out with room:
/// the focus (or the half), a run's type, and the day, as a list of the week's other days.
/// A tap applies the change and closes the sheet.
struct ChangeSessionSheet: View {
    let session: TrainingSession
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var half: BodyHalf = .upper

    var body: some View {
        ChangeSheetFrame(title: "Change \(session.title.lowercased())", subtitle: Format.weekday.string(from: session.date)) {
            switch session.modality {
            case .strength:
                ChangeSection(title: "Focus") {
                    ChipPicker(title: "Half", selection: $half, options: BodyHalf.allCases.map { ($0, "\($0.displayName) body") })
                    FocusGrid(half: half, current: session.half == half ? session.focus : nil) { focus in
                        apply { coordinator.regenerate(session, half: half, focus: focus, in: context) }
                    }
                }
            case .running:
                ChangeSection(title: "Run type") {
                    ForEach(RunKind.allCases, id: \.self) { kind in
                        // The current type at the minutes it is planned for; another at its own default.
                        let isCurrent = kind == session.runKind
                        OptionRow(symbol: Modality.running.symbolName, tint: Palette.sky, title: kind.displayName,
                                  detail: kind.changeDetail(minutes: isCurrent ? session.plannedMinutes : kind.defaultMinutes),
                                  isCurrent: isCurrent) {
                            apply { coordinator.changeRunKind(session, to: kind, in: context) }
                        }
                    }
                }
            case .yoga:
                EmptyView()
            }
            if !days.isEmpty {
                ChangeSection(title: "Day", footer: "Sessions you have already done stay where they are.") {
                    ForEach(days, id: \.id) { day in
                        DayOptionRow(date: day.date, other: day.other) {
                            apply {
                                if let other = day.other { coordinator.swapDays(session, other, in: context) }
                                else { coordinator.move(session, to: day.date, in: context) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { half = session.half ?? .upper }
    }

    /// Other sessions and rest days in the week, in day order. A day with no session is a move;
    /// one with a session is a swap.
    private var days: [(id: String, date: Date, other: TrainingSession?)] {
        let swaps = coordinator.swapCandidates(for: session, in: context).map { (id: "\($0.id)", date: $0.date, other: Optional($0)) }
        let moves = coordinator.restDays(forMoving: session, in: context).map { (id: "\($0)", date: $0, other: TrainingSession?.none) }
        return (swaps + moves).sorted { $0.date < $1.date }
    }

    private func apply(_ change: () -> Void) {
        withAnimation(Motion.reveal) { change() }
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss()
    }
}

// MARK: A rest day

/// A free day from today on: put a lift, a run or a class on it, or bring a session over.
struct RestDaySheet: View {
    let date: Date
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var half: BodyHalf = .upper

    var body: some View {
        ChangeSheetFrame(title: "Train instead", subtitle: "\(Format.weekday.string(from: date)), a rest day") {
            ChangeSection(title: "Lift") {
                ChipPicker(title: "Half", selection: $half, options: BodyHalf.allCases.map { ($0, "\($0.displayName) body") })
                FocusGrid(half: half, current: nil) { focus in
                    apply { coordinator.addStrength(on: date, half: half, focus: focus, in: context) }
                }
            }
            ChangeSection(title: "Run or class") {
                ForEach(RunKind.allCases, id: \.self) { kind in
                    OptionRow(symbol: Modality.running.symbolName, tint: Palette.sky, title: kind.displayName, detail: kind.changeDetail(minutes: kind.defaultMinutes)) {
                        apply { coordinator.addRun(on: date, kind: kind, in: context) }
                    }
                }
                OptionRow(symbol: Modality.yoga.symbolName, tint: Palette.orchid, title: "Hot yoga",
                          detail: "\(Int(coordinator.profile(in: context).yogaMinutes)) min, counts as recovery") {
                    apply { coordinator.addYoga(on: date, in: context) }
                }
            }
            let candidates = coordinator.moveCandidates(to: date, in: context)
            if !candidates.isEmpty {
                ChangeSection(title: "Move a session here") {
                    ForEach(candidates) { session in
                        DayOptionRow(date: session.date, other: session, action: "Move here") {
                            apply { coordinator.move(session, to: date, in: context) }
                        }
                    }
                }
            }
        }
    }

    private func apply(_ change: () -> Void) {
        withAnimation(Motion.reveal) { change() }
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss()
    }
}

// MARK: Pieces

/// The sheet both changes share: a title and the day under it, a close button, and sections that
/// scroll. Opens at half height, which holds the common choice, and pulls up for the rest.
private struct ChangeSheetFrame<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) { content }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .background(Palette.canvas)
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.tint(Palette.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}

private struct ChangeSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            content
            if let footer {
                Text(footer).font(.label).foregroundStyle(Palette.inkTertiary)
                    .padding(.top, 2)
            }
        }
    }
}

/// A half's focus areas as large glass tiles, two to a row. The session's current focus is lit.
private struct FocusGrid: View {
    let half: BodyHalf
    let current: FocusArea?
    let onPick: (FocusArea) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(FocusArea.areas(for: half)) { focus in
                Button { onPick(focus) } label: {
                    HStack(spacing: 8) {
                        Text(focus.displayName)
                            .font(.rowTitle)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if focus == current {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                }
                .buttonStyle(.option(isCurrent: focus == current))
                .disabled(focus == current)
                .accessibilityLabel("\(focus.displayName) focus")
                .accessibilityAddTraits(focus == current ? .isSelected : [])
            }
        }
        // Switching halves swaps the tiles in place.
        .id(half)
        .transition(.opacity.animation(Motion.settle))
    }
}

/// One choice as a full-width row: a tile, what it is, a line on what it means, and a check on
/// the current one.
private struct OptionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var isCurrent = false
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 14) {
                SessionTile(symbol: symbol, tint: tint, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.rowTitle).foregroundStyle(Palette.ink)
                    Text(detail).font(.body2.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.option(isCurrent: isCurrent))
        .disabled(isCurrent)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Another day of the week as a row, the way the Week tab draws it: the day, what is on it, and
/// what tapping does, a swap with its session or a move to an empty day.
private struct DayOptionRow: View {
    let date: Date
    let other: TrainingSession?
    var action: String?
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(Format.shortWeekday.string(from: date)).font(.label).foregroundStyle(Palette.inkSecondary)
                    Text(Format.dayNumber.string(from: date)).font(.numeralSmall).foregroundStyle(Palette.ink)
                }
                .frame(width: 40)
                if let other {
                    SessionTile(symbol: other.modality.symbolName, tint: other.modality.tint, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(other.title).font(.rowTitle).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(other.subtitle).font(.body2).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    }
                } else {
                    Text("Rest").font(.rowTitle).foregroundStyle(Palette.inkTertiary)
                }
                Spacer(minLength: 8)
                Text(action ?? (other == nil ? "Move here" : "Swap"))
                    .font(.label)
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
        .buttonStyle(.option)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Format.weekday.string(from: date)), \(other?.title ?? "rest")")
        .accessibilityHint(action ?? (other == nil ? "Moves the session to this day" : "Swaps the two sessions' days"))
    }
}

private extension RunKind {
    /// What the run is, in a line, with its minutes.
    func changeDetail(minutes: Double) -> String {
        switch self {
        case .easy: "\(Int(minutes)) min you could talk through"
        case .long: "\(Int(minutes)) min steady, the week's longest"
        case .quality: "\(Int(minutes)) min with 20 at threshold"
        }
    }
}
