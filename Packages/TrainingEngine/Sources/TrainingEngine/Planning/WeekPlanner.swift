import Foundation

/// What the athlete wants from a week. Day indices are 0 ... 6 relative to `weekStart`.
public struct PlannerPreferences: Codable, Sendable, Hashable {
    public var weekStart: Date
    public var strengthSessions: Int
    public var easyRuns: Int
    public var includeLongRun: Bool
    public var includeQualityRun: Bool
    public var yogaSessions: Int
    public var unavailableDays: Set<Int>
    /// Lets yoga share a day with another session, and an easy run share a day with an upper session.
    public var allowTwoADays: Bool
    public var preferredLongRunDay: Int?
    public var yogaMinutes: Double

    public init(
        weekStart: Date,
        strengthSessions: Int = 4,
        easyRuns: Int = 1,
        includeLongRun: Bool = true,
        includeQualityRun: Bool = false,
        yogaSessions: Int = 1,
        unavailableDays: Set<Int> = [],
        allowTwoADays: Bool = true,
        preferredLongRunDay: Int? = 5,
        yogaMinutes: Double = 60
    ) {
        self.weekStart = weekStart
        self.strengthSessions = min(6, max(0, strengthSessions))
        self.easyRuns = min(4, max(0, easyRuns))
        self.includeLongRun = includeLongRun
        self.includeQualityRun = includeQualityRun
        self.yogaSessions = min(4, max(0, yogaSessions))
        self.unavailableDays = unavailableDays
        self.allowTwoADays = allowTwoADays
        self.preferredLongRunDay = preferredLongRunDay
        self.yogaMinutes = yogaMinutes
    }

    public var runKinds: [RunKind] {
        var kinds: [RunKind] = []
        if includeLongRun { kinds.append(.long) }
        if includeQualityRun { kinds.append(.quality) }
        kinds += Array(repeating: .easy, count: easyRuns)
        return kinds
    }
}

/// The strength content the planner is scheduling: already generated so it knows the duration and load.
public struct StrengthSlot: Sendable, Hashable {
    public let half: BodyHalf
    public let focus: FocusArea
    public let estimatedMinutes: Double
    public let estimatedLoad: Double

    public init(half: BodyHalf, focus: FocusArea, estimatedMinutes: Double, estimatedLoad: Double) {
        self.half = half
        self.focus = focus
        self.estimatedMinutes = estimatedMinutes
        self.estimatedLoad = estimatedLoad
    }

    public init(_ session: GeneratedStrengthSession) {
        self.init(half: session.half, focus: session.focus, estimatedMinutes: session.estimatedMinutes, estimatedLoad: session.estimatedLoad)
    }
}

public struct PlannedSession: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case strength(index: Int, half: BodyHalf, focus: FocusArea)
        case run(RunKind)
        case yoga
    }

    public let id: String
    public let kind: Kind
    public let plannedMinutes: Double
    public let estimatedLoad: Double
    public let note: String?

    public var modality: Modality {
        switch kind {
        case .strength: .strength
        case .run: .running
        case .yoga: .yoga
        }
    }

    public var title: String {
        switch kind {
        case .strength(_, let half, let focus): "\(half.displayName) · \(focus.displayName)"
        case .run(let kind): kind.displayName
        case .yoga: "Hot yoga"
        }
    }

    /// Strength and non-easy runs are "hard" for spacing rules.
    public var isHard: Bool {
        switch kind {
        case .strength: true
        case .run(let kind): kind.isHard
        case .yoga: false
        }
    }
}

public struct PlannedDay: Sendable, Hashable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let dayIndex: Int
    public let sessions: [PlannedSession]
    public let forecast: DayForecast?

    public var isRest: Bool { sessions.isEmpty }
    public var totalLoad: Double { sessions.map(\.estimatedLoad).reduce(0, +) }
}

public struct WeekPlan: Sendable, Hashable {
    public let weekStart: Date
    public let days: [PlannedDay]
    public let targetLoad: Double
    public let readiness: Readiness
    public let notes: [String]
    public let score: Double
    /// What was asked for but did not fit the days available, cheapest to lose first.
    public let leftOut: [PlannedSession]

    public var estimatedLoad: Double { days.map(\.totalLoad).reduce(0, +) }
    public var sessions: [PlannedSession] { days.flatMap(\.sessions) }
}

/// Places the week's sessions on days.
///
/// The planner first decides *how much* to train (a weekly load target from chronic
/// load and readiness, with run durations flexing to hit it), then *when* (an exhaustive
/// scored search over day assignments with spacing, availability and weather rules).
/// Seven days is small enough that search beats heuristics: every candidate week is
/// scored and the best wins, so a rule change never produces a surprising schedule.
public enum WeekPlanner {
    public struct Input: Sendable {
        public var preferences: PlannerPreferences
        public var strength: [StrengthSlot]
        public var forecasts: [DayForecast]
        public var load: LoadSnapshot
        public var calendar: Calendar

        public init(preferences: PlannerPreferences, strength: [StrengthSlot], forecasts: [DayForecast], load: LoadSnapshot, calendar: Calendar = .current) {
            self.preferences = preferences
            self.strength = strength
            self.forecasts = forecasts
            self.load = load
            self.calendar = calendar
        }
    }

    public static func plan(_ input: Input) -> WeekPlan {
        let prefs = input.preferences
        let calendar = input.calendar
        let readiness = Readiness.from(input.load)
        var notes: [String] = [readiness.headline]

        // 1. Budget the week's load.
        let sessions = buildSessions(input: input, readiness: readiness, notes: &notes)
        let targetLoad = weeklyTarget(input: input, readiness: readiness, fallback: sessions.map(\.estimatedLoad).reduce(0, +))

        // 2. Place sessions on days.
        let forecastByIndex: [Int: DayForecast] = Dictionary(uniqueKeysWithValues: (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: calendar.startOfDay(for: prefs.weekStart)) else { return nil }
            return input.forecasts.first { calendar.isDate($0.date, inSameDayAs: date) }.map { (index, $0) }
        })
        let availableDays = (0..<7).filter { !prefs.unavailableDays.contains($0) }

        let best = bestFit(sessions: sessions, availableDays: availableDays, prefs: prefs, forecasts: forecastByIndex)
        let placed = best.placed.map { sessions[$0] }
        let leftOut = sessions.indices.filter { !best.placed.contains($0) }.map { sessions[$0] }.sorted { keepValue($0) < keepValue($1) }
        if !leftOut.isEmpty {
            notes.append("Not enough days left this week for everything, so the plan leaves out \(list(leftOut.map(describe))).")
        }

        var days: [PlannedDay] = []
        for index in 0..<7 {
            let date = calendar.date(byAdding: .day, value: index, to: calendar.startOfDay(for: prefs.weekStart)) ?? prefs.weekStart
            let todays = zip(placed, best.assignment).filter { $0.1 == index }.map(\.0).sorted { order($0) < order($1) }
            days.append(PlannedDay(date: date, dayIndex: index, sessions: todays, forecast: forecastByIndex[index]))
        }

        if let long = placed.firstIndex(where: { $0.kind == .run(.long) }), let forecast = forecastByIndex[best.assignment[long]] {
            notes.append("Long run on \(weekdayName(for: best.assignment[long], prefs: prefs, calendar: calendar)): \(forecast.condition.displayName.lowercased()), \(Int(forecast.tempMaxC.rounded()))°, \(Int((forecast.precipitationProbability * 100).rounded()))% rain.")
        }

        return WeekPlan(weekStart: prefs.weekStart, days: days, targetLoad: targetLoad, readiness: readiness, notes: notes, score: best.score, leftOut: leftOut)
    }

    // MARK: Load budgeting

    private static func weeklyTarget(input: Input, readiness: Readiness, fallback: Double) -> Double {
        if let chronic = input.load.today?.chronic, chronic > 20 {
            return chronic * 7 * readiness.weeklyLoadFactor
        }
        return fallback
    }

    private static func buildSessions(input: Input, readiness: Readiness, notes: inout [String]) -> [PlannedSession] {
        let prefs = input.preferences
        var sessions: [PlannedSession] = []

        for (index, slot) in input.strength.prefix(prefs.strengthSessions).enumerated() {
            sessions.append(PlannedSession(
                id: "strength-\(index)",
                kind: .strength(index: index, half: slot.half, focus: slot.focus),
                plannedMinutes: slot.estimatedMinutes.rounded(),
                estimatedLoad: slot.estimatedLoad,
                note: nil
            ))
        }

        let yogaRPE = 5.0
        for index in 0..<prefs.yogaSessions {
            sessions.append(PlannedSession(id: "yoga-\(index)", kind: .yoga, plannedMinutes: prefs.yogaMinutes, estimatedLoad: yogaRPE * prefs.yogaMinutes, note: nil))
        }

        // Runs flex to fill whatever load budget is left after lifting and yoga.
        let kinds = prefs.runKinds
        if !kinds.isEmpty {
            let fixedLoad = sessions.map(\.estimatedLoad).reduce(0, +)
            let defaultRunLoad = kinds.map { defaultMinutes(for: $0) * $0.defaultRPE }.reduce(0, +)
            let target = weeklyTarget(input: input, readiness: readiness, fallback: fixedLoad + defaultRunLoad)
            let runBudget = max(0, target - fixedLoad)
            let weights = kinds.map { weight(for: $0) }
            let totalWeight = weights.reduce(0, +)
            var trimmed = false
            for (index, kind) in kinds.enumerated() {
                let share = runBudget * weights[index] / totalWeight
                let raw = share / kind.defaultRPE
                let bounds = minuteBounds(for: kind)
                let minutes = (min(bounds.upperBound, max(bounds.lowerBound, raw)) / 5).rounded() * 5
                if raw < bounds.lowerBound { trimmed = true }
                sessions.append(PlannedSession(
                    id: "run-\(kind.rawValue)-\(index)",
                    kind: .run(kind),
                    plannedMinutes: minutes,
                    estimatedLoad: minutes * kind.defaultRPE,
                    note: nil
                ))
            }
            if trimmed { notes.append("Runs are at their minimum duration because lifting already fills this week's load budget.") }
        }
        return sessions
    }

    private static func defaultMinutes(for kind: RunKind) -> Double { kind.defaultMinutes }

    private static func minuteBounds(for kind: RunKind) -> ClosedRange<Double> {
        switch kind {
        case .easy: 25...60
        case .long: 45...240
        case .quality: 30...75
        }
    }

    private static func weight(for kind: RunKind) -> Double {
        switch kind {
        case .easy: 1
        case .long: 2.2
        case .quality: 1.2
        }
    }

    // MARK: Search

    /// The best week that fits. Everything is placed when it can be. When it cannot, because the
    /// week is planned late or too many days are off, the fewest sessions are left out, and of the
    /// ways to do that the best score wins once each left-out session's value is taken off. A
    /// session never lands on an unavailable day.
    private static func bestFit(
        sessions: [PlannedSession],
        availableDays: [Int],
        prefs: PlannerPreferences,
        forecasts: [Int: DayForecast]
    ) -> (placed: [Int], assignment: [Int], score: Double) {
        var best: (placed: [Int], assignment: [Int], score: Double)?
        for leaving in 0...sessions.count {
            var tried = Set<[String]>()
            for left in combinations(of: sessions.count, choosing: leaving) {
                // Identical sessions (two easy runs, two yoga classes) are interchangeable: leaving out either is the same week.
                guard tried.insert(left.map { signature(sessions[$0]) }).inserted else { continue }
                let placed = sessions.indices.filter { !left.contains($0) }
                let subset = placed.map { sessions[$0] }
                let cost = left.map { keepValue(sessions[$0]) }.reduce(0, +)
                assign(sessions: subset, availableDays: availableDays, prefs: prefs) { assignment in
                    let total = score(assignment: assignment, sessions: subset, prefs: prefs, forecasts: forecasts) - cost
                    if best == nil || total > best!.score { best = (placed, assignment, total) }
                }
            }
            if let best { return best }
        }
        return ([], [], 0)
    }

    /// What losing a session costs, on the scoring scale. Lifting is the core of the week, the long run
    /// next; an easy run is the first to go.
    private static func keepValue(_ session: PlannedSession) -> Double {
        switch session.kind {
        case .strength: 80
        case .run(.long): 60
        case .run(.quality): 40
        case .yoga: 30
        case .run(.easy): 20
        }
    }

    private static func signature(_ session: PlannedSession) -> String {
        switch session.kind {
        case .strength(let index, _, _): "strength-\(index)"
        case .run(let kind): "run-\(kind.rawValue)"
        case .yoga: "yoga"
        }
    }

    /// Every way to choose `k` of `0..<n`, as ascending index lists.
    private static func combinations(of n: Int, choosing k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard k <= n else { return [] }
        var result: [[Int]] = []
        var current: [Int] = []
        func recurse(_ start: Int) {
            if current.count == k { result.append(current); return }
            for index in start..<n where n - index >= k - current.count {
                current.append(index)
                recurse(index + 1)
                current.removeLast()
            }
        }
        recurse(0)
        return result
    }

    /// "the long run", "the posterior chain lower body session".
    private static func describe(_ session: PlannedSession) -> String {
        switch session.kind {
        case .strength(_, let half, let focus): "the \(focus.displayName.lowercased()) \(half.displayName.lowercased()) body session"
        case .run(let kind): "the \(kind.displayName.lowercased())"
        case .yoga: "hot yoga"
        }
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    /// Per-session facts hoisted out of the scoring loop so scoring allocates nothing.
    private struct Meta {
        let isStrength: Bool
        let runKind: RunKind?
        let isHard: Bool

        init(_ session: PlannedSession) {
            switch session.kind {
            case .strength: isStrength = true; runKind = nil
            case .run(let kind): isStrength = false; runKind = kind
            case .yoga: isStrength = false; runKind = nil
            }
            isHard = session.isHard
        }
    }

    /// Enumerates day assignments with pruning. Strength sessions keep their generated
    /// order (U/L/U/L) and strictly increase by day, identical sessions are assigned in
    /// increasing day order, two hard sessions never share a day and neither do two runs. Those rules
    /// turn 7^n permutations into a few thousand candidates.
    private static func assign(
        sessions: [PlannedSession],
        availableDays: [Int],
        prefs: PlannerPreferences,
        visit: ([Int]) -> Void
    ) {
        let meta = sessions.map(Meta.init)
        var current = [Int](repeating: 0, count: sessions.count)
        var hardOnDay = [Bool](repeating: false, count: 7)
        var countOnDay = [Int](repeating: 0, count: 7)
        var runOnDay = [Bool](repeating: false, count: 7)
        var longRunDay = -1

        func recurse(_ index: Int) {
            if index == sessions.count {
                visit(current)
                return
            }
            let session = sessions[index]
            let m = meta[index]
            var lowerBound = 0
            if index > 0 {
                if m.isStrength, meta[index - 1].isStrength { lowerBound = current[index - 1] + 1 }
                else if sessions[index - 1].kind == session.kind { lowerBound = current[index - 1] + 1 }
            }
            for day in availableDays where day >= lowerBound {
                if m.isHard, hardOnDay[day] { continue }
                if countOnDay[day] > 0, !prefs.allowTwoADays { continue }
                if m.isStrength, longRunDay == day { continue }
                if m.runKind == .long, hardOnDay[day] { continue }
                if m.runKind != nil, runOnDay[day] { continue } // one run a day, whatever the kinds

                current[index] = day
                countOnDay[day] += 1
                let wasHard = hardOnDay[day]
                if m.isHard { hardOnDay[day] = true }
                if m.runKind != nil { runOnDay[day] = true }
                if m.runKind == .long { longRunDay = day }

                recurse(index + 1)

                if m.runKind == .long { longRunDay = -1 }
                if m.runKind != nil { runOnDay[day] = false }
                hardOnDay[day] = wasHard
                countOnDay[day] -= 1
            }
        }
        recurse(0)
    }

    private static func score(assignment: [Int], sessions: [PlannedSession], prefs: PlannerPreferences, forecasts: [Int: DayForecast]) -> Double {
        var score = 0.0
        var strengthDays: [Int] = []
        var lowerDays: [Int] = []
        var upperDays: [Int] = []
        var runs: [(day: Int, kind: RunKind)] = []
        var yogaDays: [Int] = []
        var countOnDay = [Int](repeating: 0, count: 7)
        strengthDays.reserveCapacity(4); lowerDays.reserveCapacity(2); upperDays.reserveCapacity(2); runs.reserveCapacity(4); yogaDays.reserveCapacity(2)

        for (index, session) in sessions.enumerated() {
            let day = assignment[index]
            countOnDay[day] += 1
            switch session.kind {
            case .strength(_, let half, _):
                strengthDays.append(day)
                if half == .lower { lowerDays.append(day) } else { upperDays.append(day) }
            case .run(let kind): runs.append((day, kind))
            case .yoga: yogaDays.append(day)
            }
        }

        // Rest: a week with no empty day is a week with no recovery.
        let restDays = countOnDay.filter { $0 == 0 }.count
        score += restDays >= 1 ? 20 : -40
        if restDays >= 2 { score += 5 }

        // Strength spacing. Order is already enforced by the search.
        for i in 1..<max(1, strengthDays.count) {
            if strengthDays[i] - strengthDays[i - 1] == 1 { score -= 8 }
            if i >= 2, strengthDays[i - 2] == strengthDays[i] - 2 { score -= 50 } // three in a row
        }
        if lowerDays.count == 2, lowerDays[1] - lowerDays[0] < 3 { score -= 30 }
        if upperDays.count == 2, upperDays[1] - upperDays[0] < 3 { score -= 20 }

        // Runs versus legs: a hard run the day before or after a lower day wrecks both.
        for run in runs {
            for lower in lowerDays {
                let distance = abs(run.day - lower)
                if distance == 0 { score -= run.kind.isHard ? 200 : 60 }
                else if distance == 1 { score -= run.kind.isHard ? 60 : 10 }
            }
            for upper in upperDays where upper == run.day {
                score -= run.kind == .easy ? 15 : 60
            }
        }

        // Runs spaced out from each other.
        let sortedRuns = runs.map(\.day).sorted()
        for i in 1..<max(1, sortedRuns.count) where sortedRuns[i] - sortedRuns[i - 1] == 1 { score -= 20 }

        // Weather: runs chase the best days, the long run most of all.
        for run in runs {
            guard let forecast = forecasts[run.day] else { continue }
            let weight: Double = run.kind == .long ? 60 : 40
            score += weight * forecast.runningScore
            if forecast.precipitationProbability > 0.7 { score -= 30 }
        }
        if let preferred = prefs.preferredLongRunDay, runs.contains(where: { $0.kind == .long && $0.day == preferred }) {
            score += 25
        }

        // Yoga: an indoor session is the natural use of a wet day and of the day after legs.
        for yoga in yogaDays {
            if let forecast = forecasts[yoga] { score += 10 * (1 - forecast.runningScore) }
            if lowerDays.contains(yoga - 1) { score += 10 }
            if countOnDay[yoga] > 1 { score -= prefs.allowTwoADays ? 5 : 15 }
        }
        return score
    }

    private static func order(_ session: PlannedSession) -> Int {
        switch session.kind {
        case .run: 0
        case .strength: 1
        case .yoga: 2
        }
    }

    private static func weekdayName(for dayIndex: Int, prefs: PlannerPreferences, calendar: Calendar) -> String {
        guard let date = calendar.date(byAdding: .day, value: dayIndex, to: prefs.weekStart) else { return "day \(dayIndex + 1)" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
