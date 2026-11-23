import SwiftUI
import TrainingEngine

/// Running on Home: the predicted time for the goal's distance (5 km without a goal), how far it is
/// from the goal, and the other distances underneath. Tapping it opens the race explainer.
struct RaceCard: View {
    let outlook: RaceOutlook

    /// The distance the card leads with.
    private var lead: RaceDistance { outlook.goal?.distance ?? .fiveK }
    private var others: [RaceDistance] { RaceDistance.allCases.filter { $0 != lead } }

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    TitleIcon(symbol: Modality.running.symbolName, tint: Modality.running.tint)
                    Text("Race times").font(.rowTitle).foregroundStyle(Palette.ink)
                    InfoGlyph()
                    Spacer(minLength: 8)
                    if let verdict = RaceVerdict(outlook) { StatusChip(text: verdict.text, tint: verdict.tint) }
                }
                if let predicted = outlook.predictedMinutes(for: lead) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Format.raceTime(predicted))
                                .font(.numeralLarge)
                                .foregroundStyle(Palette.ink)
                                .contentTransition(.numericText())
                            Text("predicted \(lead.displayName)").font(.body2).foregroundStyle(Palette.inkSecondary)
                        }
                        if let goal = outlook.goal {
                            if let progress = outlook.goalProgress, !outlook.goalIsMet {
                                ProgressBar(value: progress)
                            }
                            Text(RaceExplainer.trendLine(outlook, goal: goal))
                                .font(.body2).foregroundStyle(Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(others, id: \.self) { distance in
                            figure(distance.shortName, outlook.predictedMinutes(for: distance).map(Format.raceTime))
                        }
                    }
                } else {
                    Text("\(outlook.goal.map { "Goal: \($0.distance.displayName) in \(Format.raceTime($0.minutes)). " } ?? "")Predictions show once there is a run of 3 km or more in the last eight weeks.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.body2)
            .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func figure(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.label).foregroundStyle(Palette.inkTertiary)
            Text(value ?? "–").font(.numeralSmall).foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The chip beside a race prediction: how far off the goal, or that it is met.
struct RaceVerdict {
    let text: String
    let tint: Color

    init?(_ outlook: RaceOutlook) {
        guard let goal = outlook.goal, let gap = outlook.goalGap else { return nil }
        if gap <= 0 {
            text = "Goal met"
            tint = Palette.sage
        } else {
            text = "\(Format.raceTime(gap)) off \(Format.raceTime(goal.minutes))"
            tint = Palette.accent
        }
    }
}
