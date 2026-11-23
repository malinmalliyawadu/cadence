import Foundation
import TrainingEngine

enum Format {
    static func weight(_ kg: Double?) -> String {
        guard let kg else { return "Find it" }
        if kg == 0 { return "Bodyweight" }
        return kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }

    static func kg(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    /// An estimate to the nearest half kilogram: "104.5" for an e1RM of 104.83.
    static func estimate(_ kg: Double) -> String { self.kg((kg * 2).rounded() / 2) }

    /// "85 kg × 6", or "Bodyweight × 10" with nothing added.
    static func set(_ set: PerformedSet) -> String { "\(weight(set.weightKg)) × \(set.reps)" }

    /// A movement's sets with each weight said once: "62.5 kg × 8, 8, 7", or
    /// "60 kg × 8, 8  ·  55 kg × 10" when the weight changed along the way.
    static func sets(_ sets: [PerformedSet]) -> String {
        var groups: [(weightKg: Double, reps: [Int])] = []
        for set in sets {
            if groups.last?.weightKg == set.weightKg { groups[groups.count - 1].reps.append(set.reps) } else { groups.append((set.weightKg, [set.reps])) }
        }
        // A wrapped line breaks between groups or reps, never inside "117 kg × 8".
        return groups.map { group in
            let load = "\(weight(group.weightKg)) × \(group.reps[0])".replacingOccurrences(of: " ", with: "\u{00A0}")
            return ([load] + group.reps.dropFirst().map(String.init)).joined(separator: ", ")
        }
        .joined(separator: "  ·  ")
    }

    /// A trend metric's value: "104.5 kg", "85 kg", "2,400 kg".
    static func value(_ value: Double, metric: TrendMetric) -> String {
        switch metric {
        case .oneRepMax: "\(estimate(value)) kg"
        case .topSet: "\(kg(value)) kg"
        case .volume: "\(Int(value.rounded()).formatted()) kg"
        }
    }

    /// A change in a trend metric, signed: "+4.5 kg", "−2.5 kg", "0 kg".
    static func change(_ change: Double, metric: TrendMetric) -> String {
        let magnitude = value(abs(change), metric: metric)
        if magnitude.hasPrefix("0 ") { return magnitude }
        return (change > 0 ? "+" : "−") + magnitude
    }

    static func minutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min" }
        return "\(m) min"
    }

    /// "6:05" for 365 seconds per kilometre.
    static func pace(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "2:30" for a rest with 150 seconds left. Rounds up, so the clock reads 0:00 only at the end.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "6:00 to 6:40 /km".
    static func pace(_ range: PaceRange) -> String {
        "\(pace(range.fastest)) to \(pace(range.slowest)) /km"
    }

    static func heartRate(_ range: ClosedRange<Int>) -> String { "\(range.lowerBound) to \(range.upperBound) bpm" }

    /// "132 bpm", or a dash before the watch has a reading.
    static func bpm(_ beatsPerMinute: Double?) -> String { "\(beatsPerMinute.map { "\(Int($0.rounded()))" } ?? "–") bpm" }

    /// "312 kcal" of active energy, or a dash before the watch has a reading.
    static func kcal(_ kilocalories: Double?) -> String { "\(kilocalories.map { Int($0.rounded()).formatted() } ?? "–") kcal" }

    static func temperature(_ c: Double) -> String { "\(Int(c.rounded()))°" }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func ratio(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2f", value)
    }

    static func load(_ au: Double) -> String { Int(au.rounded()).formatted() }

    /// "1.7", or a dash when the week has no spread to divide by.
    static func monotony(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "–" }

    /// "7 h 20 m" for hours asleep.
    static func sleep(_ hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) m"
    }

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
}
