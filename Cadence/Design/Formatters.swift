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

    static func temperature(_ c: Double) -> String { "\(Int(c.rounded()))°" }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func ratio(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2f", value)
    }

    static func load(_ au: Double) -> String { Int(au.rounded()).formatted() }

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

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
}
