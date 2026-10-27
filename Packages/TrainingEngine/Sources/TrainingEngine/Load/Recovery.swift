import Foundation

/// What the watch says about recovery: heart-rate variability, resting heart rate and sleep,
/// as Apple Health stores them.
public struct RecoveryReadings: Sendable, Hashable {
    public struct Reading: Sendable, Hashable {
        public var date: Date
        public var value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// HRV samples, SDNN in milliseconds. The watch takes a few a day, most of them overnight.
    public var hrv: [Reading]
    /// Daily resting heart rate, beats per minute.
    public var restingHeartRate: [Reading]
    /// Time asleep, from any source. Overlaps (watch and phone both recording) are merged.
    public var sleep: [DateInterval]

    public init(hrv: [Reading] = [], restingHeartRate: [Reading] = [], sleep: [DateInterval] = []) {
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.sleep = sleep
    }
}

public enum RecoveryLevel: String, Sendable, Hashable {
    case recovered  // every signal in its usual range
    case fair       // one small flag, not enough to change the session
    case low        // lifts trimmed 5%
    case poor       // lifts trimmed 10%

    public var displayName: String {
        switch self {
        case .recovered: "Recovered"
        case .fair: "Fair"
        case .low: "Low"
        case .poor: "Poor"
        }
    }

    /// Multiplier on today's prescribed strength loads.
    public var loadMultiplier: Double {
        switch self {
        case .recovered, .fair: 1
        case .low: 0.95
        case .poor: 0.9
        }
    }
}

/// One recovery signal against the athlete's own baseline.
public struct RecoverySignal: Sendable, Hashable {
    /// HRV in ms (7-day average), resting heart rate in bpm (3-day average), or last night's sleep in hours.
    public let current: Double
    /// The athlete's usual value, once there is enough history for one.
    public let baseline: Double?
    /// HRV only: the band a 7-day average normally sits in.
    public let normalRange: ClosedRange<Double>?
    /// How much this signal counts against recovery today. Zero when it is in its usual range.
    public let points: Int
    /// What is off, as a clause for the headline. Nil when nothing is.
    public let flag: String?
}

public struct RecoveryStatus: Sendable, Hashable {
    public let asOf: Date
    public let hrv: RecoverySignal?
    public let restingHeartRate: RecoverySignal?
    public let sleep: RecoverySignal?
    /// Nil until at least one signal can be judged: HRV and resting heart rate need a baseline, sleep a night.
    public let level: RecoveryLevel?

    public var loadMultiplier: Double { level?.loadMultiplier ?? 1 }

    /// What is off today, joined into one clause ("HRV is below your normal range and sleep was short").
    public var reason: String? {
        let flags = [hrv, restingHeartRate, sleep].compactMap { $0?.flag }
        guard let first = flags.first else { return nil }
        let joined = flags.count == 1 ? first : flags.dropLast().joined(separator: ", ") + " and " + flags.last!
        return first.prefix(1).uppercased() + joined.dropFirst()
    }

    /// What recovery means for today's lifting, which a trim can only reach before the first set.
    public enum TodaysLifting: Sendable, Hashable {
        case trimmed  // today's session is prescribed at the recovery multiplier
        case started  // a session was under way before the reading, so its loads stand
        case none     // no lifting today
    }

    public func headline(_ lifting: TodaysLifting) -> String {
        switch level {
        case nil:
            return "A week of heart-rate variability from your watch sets your normal range."
        case .recovered:
            return "HRV, resting heart rate and sleep are in your usual range. Train as planned."
        case .fair:
            return "\(reason ?? "One signal is a little off"), but not enough to change today. Train as planned."
        case .low, .poor:
            let percent = Int(((1 - loadMultiplier) * 100).rounded())
            let effect = switch lifting {
            case .trimmed: "Today's lifts are \(percent)% lighter."
            case .started: "Your session had started, so its loads stand. Ease off if the sets feel heavy."
            case .none: "Keep today's training easy."
            }
            return "\(reason ?? "Recovery is down"). \(effect)"
        }
    }
}

/// Recovery from the watch, judged against the athlete's own history rather than population norms.
///
/// - HRV follows Plews and Kiviniemi: the 7-day average of log HRV against a normal range of the
///   baseline mean plus or minus half a standard deviation of daily values over the 60 days before.
///   A single night is too noisy to act on; a week below the band is not. Apple records SDNN, not
///   rMSSD, but the method only needs a consistent measure.
/// - Resting heart rate: the last 3 days against the 30 before. Up 3 bpm is a flag, up 5 a clear one.
/// - Sleep: last night under 6 hours, or the last three nights an hour under the usual.
///
/// HRV down counts 2, resting heart rate up 1 or 2, short sleep 1. A total of 0 is recovered, 1 fair,
/// 2 or 3 low, 4 or more poor. Recovery is a today signal: it trims today's lifts, not the week.
public enum RecoveryAnalysis {
    public static func status(from readings: RecoveryReadings, asOf: Date, calendar: Calendar = .current) -> RecoveryStatus {
        let today = calendar.startOfDay(for: asOf)
        let hrv = hrvSignal(readings.hrv, today: today, calendar: calendar)
        let resting = restingSignal(readings.restingHeartRate, today: today, calendar: calendar)
        let sleep = sleepSignal(readings.sleep, today: today, calendar: calendar)

        let judged = [hrv?.baseline != nil ? hrv : nil, resting?.baseline != nil ? resting : nil, sleep].compactMap { $0 }
        let level: RecoveryLevel? = judged.isEmpty ? nil : {
            switch judged.map(\.points).reduce(0, +) {
            case 0: .recovered
            case 1: .fair
            case 2...3: .low
            default: .poor
            }
        }()
        return RecoveryStatus(asOf: asOf, hrv: hrv, restingHeartRate: resting, sleep: sleep, level: level)
    }

    // MARK: Signals

    static func hrvSignal(_ readings: [RecoveryReadings.Reading], today: Date, calendar: Calendar) -> RecoverySignal? {
        // Log first: HRV is skewed, and a drop from 60 to 50 ms matters more than one from 120 to 110.
        let daily = dailyMeans(readings.filter { $0.value > 0 }.map { .init(date: $0.date, value: log($0.value)) }, calendar: calendar)
        let recent = values(in: daily, from: -6, through: 0, today: today, calendar: calendar)
        guard recent.count >= 3 else { return nil }
        let current = mean(recent)
        let base = values(in: daily, from: -60, through: -7, today: today, calendar: calendar)
        guard base.count >= 14 else {
            return RecoverySignal(current: exp(current), baseline: nil, normalRange: nil, points: 0, flag: nil)
        }
        let baseMean = mean(base)
        let band = 0.5 * standardDeviation(base)
        let low = current < baseMean - band
        return RecoverySignal(
            current: exp(current),
            baseline: exp(baseMean),
            normalRange: exp(baseMean - band)...exp(baseMean + band),
            points: low ? 2 : 0,
            flag: low ? "HRV is below your normal range" : nil
        )
    }

    static func restingSignal(_ readings: [RecoveryReadings.Reading], today: Date, calendar: Calendar) -> RecoverySignal? {
        let daily = dailyMeans(readings, calendar: calendar)
        let recent = values(in: daily, from: -2, through: 0, today: today, calendar: calendar)
        // Today's figure arrives late in the day, so two of the last three days will do.
        guard recent.count >= 2 else { return nil }
        let current = mean(recent)
        let base = values(in: daily, from: -33, through: -3, today: today, calendar: calendar)
        guard base.count >= 10 else {
            return RecoverySignal(current: current, baseline: nil, normalRange: nil, points: 0, flag: nil)
        }
        let baseMean = mean(base)
        let rise = current - baseMean
        let points = rise >= 5 ? 2 : rise >= 3 ? 1 : 0
        return RecoverySignal(
            current: current,
            baseline: baseMean,
            normalRange: nil,
            points: points,
            flag: points > 0 ? "resting heart rate is up \(Int(rise.rounded())) bpm" : nil
        )
    }

    static func sleepSignal(_ intervals: [DateInterval], today: Date, calendar: Calendar) -> RecoverySignal? {
        let nights = nightlySleepHours(intervals, calendar: calendar)
        guard let lastNight = nights[today], lastNight > 0 else { return nil }
        let recent = values(in: nights, from: -2, through: 0, today: today, calendar: calendar)
        let base = values(in: nights, from: -31, through: -3, today: today, calendar: calendar)
        let baseline = base.count >= 7 ? mean(base) : nil
        let flag: String? = if lastNight < 6 {
            "sleep was short"
        } else if let baseline, mean(recent) < baseline - 1 {
            "you have slept an hour less than usual"
        } else {
            nil
        }
        return RecoverySignal(current: lastNight, baseline: baseline, normalRange: nil, points: flag == nil ? 0 : 1, flag: flag)
    }

    // MARK: Helpers

    /// Hours asleep per night, keyed by the day the night ends on. Sleep ending before 6 pm belongs
    /// to that day, so a lie-in still counts as last night; anything later starts the next night.
    static func nightlySleepHours(_ intervals: [DateInterval], calendar: Calendar) -> [Date: Double] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var nights: [Date: Double] = [:]
        for interval in merged {
            let night = calendar.startOfDay(for: interval.end.addingTimeInterval(6 * 3600))
            nights[night, default: 0] += interval.duration / 3600
        }
        return nights
    }

    private static func dailyMeans(_ readings: [RecoveryReadings.Reading], calendar: Calendar) -> [Date: Double] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }.mapValues { mean($0.map(\.value)) }
    }

    /// Values for the days `from` to `through` relative to today, inclusive, skipping days without one.
    private static func values(in daily: [Date: Double], from: Int, through: Int, today: Date, calendar: Calendar) -> [Double] {
        (from...through).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).flatMap { daily[$0] }
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        return (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(values.count - 1)).squareRoot()
    }
}
