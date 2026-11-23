import SwiftData
import SwiftUI
import TrainingEngine

/// Settings, Race goal: a distance and a time typed as on a watch ("20:00", "1:45:00").
struct RaceGoalSection: View {
    @Bindable var profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @State private var timeText = ""
    @FocusState private var editingTime: Bool

    var body: some View {
        Section {
            Picker("Distance", selection: Binding(get: { profile.runGoal?.distance }, set: setDistance)) {
                Text("No goal").tag(RaceDistance?.none)
                ForEach(RaceDistance.goalDistances, id: \.self) { Text($0.displayName).tag(RaceDistance?.some($0)) }
            }
            if profile.runGoal != nil {
                LabeledContent("Time") {
                    TextField("20:00", text: $timeText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($editingTime)
                        .submitLabel(.done)
                        .onSubmit(commitTime)
                }
            }
        } header: {
            Text("Race goal").formHeader()
        } footer: {
            Text(footer).formFooter()
        }
        .onAppear { timeText = profile.runGoal.map { Format.raceTime($0.minutes) } ?? "" }
        .onChange(of: editingTime) { _, editing in if !editing { commitTime() } }
    }

    private var footer: String {
        guard profile.runGoal != nil else {
            return "Set one and the week's quality run turns over between intervals, threshold and speed reps, and Home shows how far off it you are."
        }
        if Self.minutes(from: timeText) == nil { return "Type a time like 20:00, or 1:45:00 past the hour." }
        return "The quality run is on and turns over between intervals, threshold and speed reps, paced from your runs now. A week already planned changes when it is next planned."
    }

    private func setDistance(_ distance: RaceDistance?) {
        guard let distance else {
            coordinator.setRunGoal(nil, in: context)
            timeText = ""
            return
        }
        // Start from where the athlete is: today's prediction to the minute, else a round number.
        let predicted = coordinator.raceOutlook(in: context).predictedMinutes(for: distance)
        let minutes = profile.runGoal?.distance == distance ? profile.runGoal!.minutes
            : predicted.map { $0.rounded(.down) } ?? (distance == .fiveK ? 25 : 52)
        coordinator.setRunGoal(RunGoal(distance: distance, minutes: minutes), in: context)
        timeText = Format.raceTime(minutes)
    }

    private func commitTime() {
        guard let goal = profile.runGoal else { return }
        guard let minutes = Self.minutes(from: timeText) else {
            timeText = Format.raceTime(goal.minutes)
            return
        }
        if minutes != goal.minutes { coordinator.setRunGoal(RunGoal(distance: goal.distance, minutes: minutes), in: context) }
        timeText = Format.raceTime(minutes)
    }

    /// "20:00" or "20" as minutes, "1:45:00" as hours. Nil for anything else, or a time no one runs
    /// a 5 or 10 km in.
    static func minutes(from text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        let minutes: Double
        switch values.count {
        case 1: minutes = Double(values[0])
        case 2 where values[1] < 60: minutes = Double(values[0]) + Double(values[1]) / 60
        case 3 where values[1] < 60 && values[2] < 60: minutes = Double(values[0] * 60 + values[1]) + Double(values[2]) / 60
        default: return nil
        }
        return (10...300).contains(minutes) ? minutes : nil
    }
}
