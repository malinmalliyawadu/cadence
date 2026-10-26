import Foundation

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

    static func temperature(_ c: Double) -> String { "\(Int(c.rounded()))°" }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func ratio(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2f", value)
    }

    static func load(_ au: Double) -> String { "\(Int(au.rounded()))" }

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
