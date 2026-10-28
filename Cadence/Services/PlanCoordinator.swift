import Foundation
import Observation
import SwiftData
import TrainingEngine

/// Bridges the store and the engine: builds history, runs the generator and planner,
/// persists the week, and records completions.
@MainActor
@Observable
final class PlanCoordinator {
    enum Phase: Equatable {
        case idle
        case planning
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastPlan: WeekPlan?
    private(set) var forecastError: String?
    /// Today's recovery from the watch. Nil until Apple Health has been read this launch.
    private(set) var recovery: RecoveryStatus?

    let forecastProvider: any ForecastProviding
    var calendar: Calendar

    init(forecastProvider: any ForecastProviding = OpenMeteoService(), calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2 // Monday
        self.forecastProvider = forecastProvider
        self.calendar = calendar
    }

    // MARK: Profile

    func profile(in context: ModelContext) -> AthleteProfile {
        if let existing = try? context.fetch(FetchDescriptor<AthleteProfile>()).first { return existing }
        let profile = AthleteProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    // MARK: Dates

    func weekStart(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    // MARK: History

    func history(in context: ModelContext) -> [ExerciseHistoryEntry] {
        let completed = SessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.statusRaw == completed })
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.flatMap { $0.exercises.compactMap(\.historyEntry) }
    }

    func loadEntries(in context: ModelContext) -> [LoadEntry] {
        let completed = SessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.statusRaw == completed })
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.compactMap(\.loadEntry)
    }

    func loadSnapshot(in context: ModelContext, asOf date: Date = .now) -> LoadSnapshot {
        LoadAnalysis.snapshot(entries: loadEntries(in: context), asOf: date, calendar: calendar)
    }

    /// The snapshot to show the athlete. Until something is logged today, "today" is a zero
    /// that would drag the acute line down every morning, so the reference day is yesterday.
    func displaySnapshot(entries: [LoadEntry], now: Date = .now) -> LoadSnapshot {
        let hasLoadToday = entries.contains { calendar.isDate($0.date, inSameDayAs: now) }
        return hasLoadToday
            ? LoadAnalysis.snapshot(entries: entries, asOf: now, calendar: calendar)
            : LoadAnalysis.snapshot(entries: entries, planningOn: now, calendar: calendar)
    }

    func forecasts(in context: ModelContext) -> [DayForecast] {
        let descriptor = FetchDescriptor<ForecastDay>(sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.forecast)
    }

    // MARK: Recovery

    /// Readiness for a session on `date`: load up to the day before, and recovery if the session is today.
    func readiness(on date: Date, entries: [LoadEntry]) -> Readiness {
        let snapshot = LoadAnalysis.snapshot(entries: entries, planningOn: date, calendar: calendar)
        let todays = recovery.flatMap { calendar.isDate($0.asOf, inSameDayAs: date) && calendar.isDateInToday(date) ? $0 : nil }
        return Readiness.from(snapshot, recovery: todays)
    }

    func updateRecovery(_ status: RecoveryStatus, in context: ModelContext) {
        recovery = status
        applyRecovery(in: context)
    }

    /// Re-prescribes today's strength session when recovery calls for different loads than it is
    /// prescribed at. Only before anything is logged, and only movements whose sets the athlete
    /// has not planned by hand. Recovery is a today signal, so later sessions are left alone.
    private func applyRecovery(in context: ModelContext) {
        let today = calendar.startOfDay(for: .now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let strength = Modality.strength.rawValue
        let planned = SessionStatus.planned.rawValue
        let descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate {
            $0.modalityRaw == strength && $0.statusRaw == planned && $0.date >= today && $0.date < tomorrow
        })
        let sessions = ((try? context.fetch(descriptor)) ?? []).filter { $0.loggedSetCount == 0 }
        guard !sessions.isEmpty else { return }
        let entries = loadEntries(in: context)
        let history = history(in: context)
        let bodyweight = profile(in: context).bodyweightKg
        for session in sessions {
            let readiness = readiness(on: session.date, entries: entries)
            let factor = readiness.recovery?.loadMultiplier ?? 1
            guard session.recoveryFactor != factor else { continue }
            for exercise in session.exercises where exercise.sets.isEmpty {
                guard let movement = exercise.exercise else { continue }
                let result = Progression.nextLoad(for: movement, history: history, repRange: exercise.repRange, targetRIR: exercise.targetRIR,
                                                  readiness: readiness.loadMultiplier, readinessReason: readiness.cutReason, bodyweightKg: bodyweight)
                exercise.prescribedWeightKg = result.weightKg
                exercise.rationale = result.rationale
            }
            session.recoveryFactor = factor
        }
        try? context.save()
    }

    // MARK: Forecast

    func refreshForecast(in context: ModelContext) async {
        let profile = profile(in: context)
        do {
            let days = try await forecastProvider.forecast(latitude: profile.latitude, longitude: profile.longitude, days: 10)
            let existing = (try? context.fetch(FetchDescriptor<ForecastDay>())) ?? []
            var byDate = Dictionary(uniqueKeysWithValues: existing.map { ($0.date, $0) })
            for day in days {
                if let record = byDate[day.date] {
                    record.update(from: day)
                    byDate[day.date] = nil
                } else {
                    context.insert(ForecastDay(day))
                }
            }
            // Drop stale days that are no longer in the forecast window and are in the past.
            let today = calendar.startOfDay(for: .now)
            for stale in byDate.values where stale.date < today { context.delete(stale) }
            try context.save()
            forecastError = nil
        } catch {
            forecastError = "Forecast unavailable. Runs were placed without weather."
        }
    }

    // MARK: Planning

    /// Plans (or re-plans) the week containing `date`. Completed and skipped sessions are
    /// kept; untouched planned sessions are replaced. Days already past are not planned.
    func planWeek(containing date: Date = .now, in context: ModelContext) async {
        phase = .planning
        defer { phase = .idle }

        let profile = profile(in: context)
        let start = weekStart(containing: date)
        let today = calendar.startOfDay(for: date)

        // 1. Clear this week's untouched sessions. A lift with sets logged is under way, so it stays.
        let weekSessions = sessions(weekStart: start, in: context)
        let untouched = { (session: TrainingSession) in session.status == .planned && session.date >= today && session.loggedSetCount == 0 }
        for session in weekSessions where untouched(session) {
            context.delete(session)
        }
        let kept = weekSessions.filter { !untouched($0) }

        // 2. Work out what is left to place this week.
        var prefs = profile.plannerPreferences(weekStart: start)
        let keptStrength = kept.filter { $0.modality == .strength }
        let keptYoga = kept.filter { $0.modality == .yoga }.count
        let keptRuns = kept.filter { $0.modality == .running }
        prefs.strengthSessions = max(0, prefs.strengthSessions - keptStrength.count)
        prefs.yogaSessions = max(0, prefs.yogaSessions - keptYoga)
        if keptRuns.contains(where: { $0.runKind == .long }) { prefs.includeLongRun = false }
        if keptRuns.contains(where: { $0.runKind == .quality }) { prefs.includeQualityRun = false }
        prefs.easyRuns = max(0, prefs.easyRuns - keptRuns.filter { $0.runKind == .easy }.count)
        for index in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: index, to: start) else { continue }
            if day < today { prefs.unavailableDays.insert(index) }
            // A day with a kept hard session is full.
            if kept.contains(where: { calendar.isDate($0.date, inSameDayAs: day) && ($0.modality == .strength || $0.runKind?.isHard == true) }) {
                prefs.unavailableDays.insert(index)
            }
        }

        // 3. Generate strength content.
        let history = history(in: context)
        let snapshot = LoadAnalysis.snapshot(entries: loadEntries(in: context), planningOn: today, calendar: calendar)
        let readiness = Readiness.from(snapshot)
        let lastHalf = lastCompletedStrength(in: context)?.half
        var half: BodyHalf = lastHalf == .upper ? .lower : .upper
        if let lastThisWeek = keptStrength.sorted(by: { $0.date < $1.date }).last?.half {
            half = lastThisWeek == .upper ? .lower : .upper
        }
        var upperFocus = profile.nextUpperFocus
        var lowerFocus = profile.nextLowerFocus
        var recentUpper = Set(lastCompletedStrength(half: .upper, in: context)?.exercises.map(\.exerciseID) ?? [])
        var recentLower = Set(lastCompletedStrength(half: .lower, in: context)?.exercises.map(\.exerciseID) ?? [])
        var generated: [GeneratedStrengthSession] = []
        for index in 0..<prefs.strengthSessions {
            let focus = half == .upper ? upperFocus : lowerFocus
            let session = WorkoutGenerator.generate(StrengthSessionRequest(
                half: half,
                focus: focus,
                availableEquipment: profile.equipment,
                recentExerciseIDs: half == .upper ? recentUpper : recentLower,
                history: history,
                readiness: readiness.loadMultiplier,
                setReduction: readiness.setReduction,
                variationSeed: Int(start.timeIntervalSince1970 / 86_400) + index,
                bodyweightKg: profile.bodyweightKg,
                alwaysIncluded: profile.alwaysIncluded(for: half)
            ))
            generated.append(session)
            let ids = Set(session.prescriptions.map(\.exercise.id))
            if half == .upper { upperFocus = focus.next; recentUpper = ids } else { lowerFocus = focus.next; recentLower = ids }
            half = half == .upper ? .lower : .upper
        }

        // 4. Place everything.
        let input = WeekPlanner.Input(
            preferences: prefs,
            strength: generated.map(StrengthSlot.init),
            forecasts: forecasts(in: context),
            load: snapshot,
            calendar: calendar
        )
        let plan = await Task.detached(priority: .userInitiated) { WeekPlanner.plan(input) }.value
        lastPlan = plan

        // 5. Persist.
        for day in plan.days {
            for (order, planned) in day.sessions.enumerated() {
                let date = calendar.date(byAdding: .hour, value: 6 + order, to: day.date) ?? day.date
                let session = TrainingSession(date: date, modality: planned.modality, plannedMinutes: planned.plannedMinutes, weekStart: start)
                switch planned.kind {
                case .strength(let index, let half, let focus):
                    session.half = half
                    session.focus = focus
                    let content = generated[index]
                    session.exercises = content.prescriptions.enumerated().map { PlannedExercise(prescription: $1, order: $0) }
                case .run(let kind):
                    session.runKind = kind
                case .yoga:
                    break
                }
                context.insert(session)
            }
        }
        do { try context.save() } catch { phase = .failed(error.localizedDescription) }
        applyRecovery(in: context)
    }

    func sessions(weekStart: Date, in context: ModelContext) -> [TrainingSession] {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.date >= weekStart && $0.date < end }, sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func lastCompletedStrength(half: BodyHalf? = nil, in context: ModelContext) -> TrainingSession? {
        let completed = SessionStatus.completed.rawValue
        let strength = Modality.strength.rawValue
        var descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.statusRaw == completed && $0.modalityRaw == strength }, sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        if let half {
            let raw = half.rawValue
            descriptor.predicate = #Predicate { $0.statusRaw == completed && $0.modalityRaw == strength && $0.halfRaw == raw }
        }
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Logging

    /// Marks a session done. Strength sessions take the effort rated on finishing (or from a
    /// watch workout), else derive it from the logged RIR, and advance the focus rotation so the
    /// next plan picks up where this one left off. Minutes already taken from an Apple Health
    /// workout are kept.
    func complete(_ session: TrainingSession, at date: Date = .now, minutes: Double? = nil, rpe: Double? = nil, distanceKm: Double? = nil, in context: ModelContext) {
        session.status = .completed
        session.completedAt = date
        session.actualMinutes = minutes ?? session.actualMinutes ?? session.plannedMinutes
        if let rpe { session.rpe = rpe }
        if let distanceKm { session.distanceKm = distanceKm }
        if session.modality == .strength {
            session.rpe = rpe ?? suggestedEffort(for: session)
            let profile = profile(in: context)
            if let focus = session.focus {
                if focus.half == .upper { profile.nextUpperFocus = focus.next } else { profile.nextLowerFocus = focus.next }
            }
        }
        try? context.save()
    }

    /// Where the effort question starts for a strength session: the RPE its reps in reserve imply.
    func suggestedEffort(for session: TrainingSession) -> Double {
        TrainingLoad.strengthSessionRPE(meanRIR: session.loggedMeanRIR ?? session.meanTargetRIR)
    }

    func skip(_ session: TrainingSession, in context: ModelContext) {
        session.status = .skipped
        try? context.save()
    }

    func deleteAllSessions(in context: ModelContext) {
        try? context.delete(model: TrainingSession.self)
        try? context.save()
        lastPlan = nil
    }

    func reopen(_ session: TrainingSession, in context: ModelContext) {
        session.status = .planned
        session.completedAt = nil
        session.actualMinutes = nil
        try? context.save()
    }

    /// Rebuilds a planned strength session for a different half or focus. Only allowed
    /// before anything is logged, so history stays truthful.
    func regenerate(_ session: TrainingSession, half: BodyHalf, focus: FocusArea, in context: ModelContext) {
        guard session.modality == .strength, session.status == .planned, session.loggedSetCount == 0, focus.half == half else { return }
        let profile = profile(in: context)
        let readiness = readiness(on: session.date, entries: loadEntries(in: context))
        let recent = Set(lastCompletedStrength(half: half, in: context)?.exercises.map(\.exerciseID) ?? [])
        let generated = WorkoutGenerator.generate(StrengthSessionRequest(
            half: half,
            focus: focus,
            availableEquipment: profile.equipment,
            recentExerciseIDs: recent,
            history: history(in: context),
            readiness: readiness.loadMultiplier,
            readinessReason: readiness.cutReason,
            setReduction: readiness.setReduction,
            variationSeed: Int(session.date.timeIntervalSince1970 / 86_400),
            bodyweightKg: profile.bodyweightKg,
            alwaysIncluded: profile.alwaysIncluded(for: half)
        ))
        for exercise in session.exercises { context.delete(exercise) }
        session.exercises = generated.prescriptions.enumerated().map { PlannedExercise(prescription: $1, order: $0) }
        session.half = half
        session.focus = focus
        session.recoveryFactor = readiness.recovery?.loadMultiplier ?? 1
        session.plannedMinutes = generated.estimatedMinutes.rounded()
        try? context.save()
    }

    /// Sets the movements added to every session of a half, and brings upcoming sessions that
    /// have nothing logged into line: new ones are added where missing, dropped ones are removed.
    func setAlwaysIncluded(_ ids: [String], for half: BodyHalf, in context: ModelContext) {
        let profile = profile(in: context)
        let previous = profile.alwaysIncluded(for: half)
        if half == .upper { profile.alwaysIncludedUpper = ids } else { profile.alwaysIncludedLower = ids }
        let added = ids.filter { !previous.contains($0) }.compactMap(ExerciseLibrary.exercise(id:))
        let removed = Set(previous).subtracting(ids)

        let today = calendar.startOfDay(for: .now)
        let strength = Modality.strength.rawValue
        let planned = SessionStatus.planned.rawValue
        let halfRaw = half.rawValue
        let descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate {
            $0.modalityRaw == strength && $0.statusRaw == planned && $0.halfRaw == halfRaw && $0.date >= today
        })
        let upcoming = ((try? context.fetch(descriptor)) ?? []).filter { $0.loggedSetCount == 0 }
        let history = history(in: context)
        let entries = loadEntries(in: context)
        for session in upcoming {
            guard let focus = session.focus else { continue }
            let dropped = session.exercises.filter { removed.contains($0.exerciseID) }
            session.exercises.removeAll { removed.contains($0.exerciseID) }
            for exercise in dropped { context.delete(exercise) }

            let readiness = readiness(on: session.date, entries: entries)
            let request = StrengthSessionRequest(
                half: half,
                focus: focus,
                history: history,
                readiness: readiness.loadMultiplier,
                readinessReason: readiness.cutReason,
                setReduction: readiness.setReduction,
                bodyweightKg: profile.bodyweightKg
            )
            var ordered = session.orderedExercises
            for exercise in added where !ordered.contains(where: { $0.exerciseID == exercise.id }) {
                let index = WorkoutGenerator.insertionIndex(for: exercise.role, in: ordered.map { $0.exercise?.role ?? .isolation })
                let new = PlannedExercise(prescription: WorkoutGenerator.prescription(adding: exercise, for: request), order: index)
                session.exercises.append(new)
                ordered.insert(new, at: index)
            }
            for (order, exercise) in ordered.enumerated() { exercise.order = order }
            refreshMinutes(session)
        }
        try? context.save()
    }

    /// Exchanges the days of two planned sessions. Everything else about them stays.
    func swapDays(_ a: TrainingSession, _ b: TrainingSession, in context: ModelContext) {
        guard a.status == .planned, b.status == .planned, a != b else { return }
        let dateA = a.date
        a.date = b.date
        b.date = dateA
        try? context.save()
    }

    /// Moves a planned session to another day, keeping its time of day. Nothing logged yet, so its history stays put.
    func move(_ session: TrainingSession, to day: Date, in context: ModelContext) {
        guard session.status == .planned, session.loggedSetCount == 0 else { return }
        let time = calendar.dateComponents([.hour, .minute], from: session.date)
        let start = calendar.startOfDay(for: day)
        session.date = calendar.date(byAdding: time, to: start) ?? start
        session.weekStart = weekStart(containing: start)
        try? context.save()
        applyRecovery(in: context)
    }

    /// Puts a lift on a day the plan left free.
    func addStrength(on day: Date, half: BodyHalf, focus: FocusArea, in context: ModelContext) {
        let session = insertSession(on: day, modality: .strength, minutes: 0, in: context)
        regenerate(session, half: half, focus: focus, in: context)
    }

    func addRun(on day: Date, kind: RunKind, in context: ModelContext) {
        let session = insertSession(on: day, modality: .running, minutes: kind.defaultMinutes, in: context)
        session.runKind = kind
        try? context.save()
    }

    func addYoga(on day: Date, in context: ModelContext) {
        _ = insertSession(on: day, modality: .yoga, minutes: profile(in: context).yogaMinutes, in: context)
        try? context.save()
    }

    /// A planned session at 6 am, the hour the planner gives a day's first session.
    private func insertSession(on day: Date, modality: Modality, minutes: Double, in context: ModelContext) -> TrainingSession {
        let start = calendar.startOfDay(for: day)
        let session = TrainingSession(date: calendar.date(byAdding: .hour, value: 6, to: start) ?? start, modality: modality,
                                      plannedMinutes: minutes, weekStart: weekStart(containing: start))
        context.insert(session)
        return session
    }

    /// Planned sessions elsewhere in the week that could move to `day`. A missed one earlier in
    /// the week counts, so it can be made up; one with sets logged is under way and stays.
    func moveCandidates(to day: Date, in context: ModelContext) -> [TrainingSession] {
        sessions(weekStart: weekStart(containing: day), in: context).filter {
            $0.status == .planned && $0.loggedSetCount == 0 && !calendar.isDate($0.date, inSameDayAs: day)
        }
    }

    /// Days from today on in the session's week with nothing planned or done, for moving it to.
    func restDays(forMoving session: TrainingSession, in context: ModelContext) -> [Date] {
        let week = sessions(weekStart: session.weekStart, in: context).filter { $0.status != .skipped }
        let today = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: session.weekStart) }.filter { day in
            day >= today && !calendar.isDate(day, inSameDayAs: session.date) && !week.contains { calendar.isDate($0.date, inSameDayAs: day) }
        }
    }

    /// Changes a planned run's type. Minutes follow the type's default unless the athlete already shortened it.
    func changeRunKind(_ session: TrainingSession, to kind: RunKind, in context: ModelContext) {
        guard session.modality == .running, session.status == .planned else { return }
        session.runKind = kind
        session.plannedMinutes = kind.defaultMinutes
        try? context.save()
    }

    /// Other planned sessions in the same week, for swapping.
    func swapCandidates(for session: TrainingSession, in context: ModelContext) -> [TrainingSession] {
        sessions(weekStart: session.weekStart, in: context).filter { $0 != session && $0.status == .planned && !calendar.isDate($0.date, inSameDayAs: session.date) }
    }

    /// Every movement that could replace this one, best fit for the slot and the session's focus first.
    func swapOptions(for exercise: PlannedExercise, in context: ModelContext) -> [SwapOption] {
        guard let current = exercise.exercise, let session = exercise.session else { return [] }
        let familiarity = history(in: context).reduce(into: [String: Int]()) { counts, entry in
            if !entry.workingSets.isEmpty { counts[entry.exerciseID, default: 0] += 1 }
        }
        return SwapRanking.options(
            replacing: current,
            focus: session.focus,
            excluding: Set(session.exercises.map(\.exerciseID)),
            equipment: profile(in: context).equipment,
            familiarity: familiarity
        )
    }

    /// What the replacement would be prescribed at in this slot, from its own history and the
    /// session's readiness.
    func prescription(for replacement: Exercise, in exercise: PlannedExercise, history: [ExerciseHistoryEntry], readiness: Readiness?, bodyweightKg: Double) -> ProgressionResult {
        Progression.nextLoad(for: replacement, history: history, repRange: exercise.repRange, targetRIR: exercise.targetRIR,
                             readiness: readiness?.loadMultiplier ?? 1, readinessReason: readiness?.cutReason, bodyweightKg: bodyweightKg)
    }

    /// Readiness for the session a movement belongs to.
    func readiness(for exercise: PlannedExercise, in context: ModelContext) -> Readiness? {
        exercise.session.map { readiness(on: $0.date, entries: loadEntries(in: context)) }
    }

    /// Puts `replacement` in this slot, keeping the scheme and prescribing its load from its own history.
    func swap(_ exercise: PlannedExercise, to replacement: Exercise, in context: ModelContext) {
        let result = prescription(for: replacement, in: exercise, history: history(in: context), readiness: readiness(for: exercise, in: context), bodyweightKg: profile(in: context).bodyweightKg)
        exercise.exerciseID = replacement.id
        exercise.prescribedWeightKg = result.weightKg
        exercise.rationale = result.rationale
        exercise.warmUpsDone = 0
        for set in exercise.sets { context.delete(set) }
        exercise.sets = []
        try? context.save()
    }

    // MARK: Set plan

    /// Ticks warm-ups off up to `count`, or back to it when undoing one.
    func setWarmUpsDone(_ count: Int, for exercise: PlannedExercise, in context: ModelContext) {
        exercise.warmUpsDone = min(max(0, count), exercise.warmUps.count)
        try? context.save()
    }

    /// Logs the set at `index`, keeping any planned record so the row does not move.
    func logSet(_ exercise: PlannedExercise, at index: Int, weightKg: Double, reps: Int, rir: Int?, in context: ModelContext) {
        let set = exercise.record(at: index) ?? {
            let new = SetRecord(index: index, weightKg: weightKg, reps: reps)
            new.exercise = exercise
            exercise.sets.append(new)
            return new
        }()
        set.weightKg = weightKg
        set.reps = reps
        set.rir = rir
        set.completedAt = .now
        try? context.save()
    }

    /// Puts a logged set back in the plan at the values it was logged at.
    func unlogSet(_ set: SetRecord, in context: ModelContext) {
        set.completedAt = nil
        set.rir = nil
        try? context.save()
    }

    /// Changes what an upcoming set is planned at.
    func planSet(_ exercise: PlannedExercise, at index: Int, weightKg: Double, reps: Int, in context: ModelContext) {
        if let set = exercise.record(at: index) {
            set.weightKg = weightKg
            set.reps = reps
        } else {
            let set = SetRecord(index: index, weightKg: weightKg, reps: reps)
            set.exercise = exercise
            exercise.sets.append(set)
        }
        try? context.save()
    }

    /// Adds a set at the end, planned like the one before it.
    func addSet(to exercise: PlannedExercise, in context: ModelContext) {
        guard exercise.targetSets < 10 else { return }
        let last = exercise.target(at: exercise.targetSets - 1)
        exercise.targetSets += 1
        refreshMinutes(exercise.session)
        planSet(exercise, at: exercise.targetSets - 1, weightKg: last.weightKg, reps: last.reps, in: context)
    }

    /// Removes the last set, as long as it has not been logged and one set remains.
    func removeLastSet(from exercise: PlannedExercise, in context: ModelContext) {
        let last = exercise.targetSets - 1
        guard last > 0, exercise.record(at: last)?.completedAt == nil else { return }
        if let planned = exercise.record(at: last) { context.delete(planned) }
        exercise.targetSets = last
        refreshMinutes(exercise.session)
        try? context.save()
    }

    /// Switches a movement to a different scheme for this session and works the weight out from
    /// the athlete's estimated max at the new rep range. Only before anything is logged.
    func apply(_ preset: SchemePreset, to exercise: PlannedExercise, in context: ModelContext) {
        guard exercise.completedSets.isEmpty, let movement = exercise.exercise else { return }
        exercise.targetSets = preset.sets
        exercise.repLower = preset.reps.lowerBound
        exercise.repUpper = preset.reps.upperBound
        for set in exercise.sets { context.delete(set) }
        exercise.sets = []
        refreshMinutes(exercise.session)
        let history = history(in: context)
        let bodyweight = profile(in: context).bodyweightKg
        if let full = Progression.load(for: movement, history: history, reps: preset.reps.lowerBound, rir: exercise.targetRIR, bodyweightKg: bodyweight) {
            // A stalled movement is on a deload week whatever the scheme, so keep it 10% lighter.
            let deload = Progression.nextLoad(for: movement, history: history, repRange: preset.reps, targetRIR: exercise.targetRIR, bodyweightKg: bodyweight).decision == .deload
            let weight = deload ? roundToIncrement(full * 0.9, increment: movement.equipment.incrementKg) : full
            exercise.prescribedWeightKg = weight
            exercise.rationale = deload
                ? "\(preset.name) today: \(preset.sets) × \(preset.reps.lowerBound) to \(preset.reps.upperBound). Still a deload week, so \(Format.weight(weight)) is 10% under what your estimated max gives for \(preset.reps.lowerBound) reps."
                : "\(preset.name) today: \(preset.sets) × \(preset.reps.lowerBound) to \(preset.reps.upperBound). \(Format.weight(weight)) is \(preset.reps.lowerBound) reps at \(exercise.targetRIR) in reserve from your estimated max."
        } else {
            exercise.rationale = "\(preset.name) today: \(preset.sets) × \(preset.reps.lowerBound) to \(preset.reps.upperBound). No history on this movement yet, so work up to a weight where \(preset.reps.lowerBound) reps leaves \(exercise.targetRIR) in reserve."
        }
        try? context.save()
    }

    /// Re-estimates a strength session's length after its sets or reps change, on the same model
    /// the generator uses, so the duration and the planned load stay honest.
    private func refreshMinutes(_ session: TrainingSession?) {
        guard let session, session.modality == .strength else { return }
        let work = session.exercises.compactMap { planned in
            planned.exercise.map {
                ExercisePrescription(exercise: $0, sets: planned.targetSets, repRange: planned.repRange, targetRIR: planned.targetRIR,
                                     weightKg: planned.prescribedWeightKg, isFocus: planned.isFocus, rationale: planned.rationale).estimatedMinutes
            }
        }
        session.plannedMinutes = (8 + work.reduce(0, +)).rounded() // 8 minutes of warm-up, as the generator assumes
    }

    // MARK: Runs

    /// Pace and heart-rate targets for a run, from the last eight weeks of runs and the athlete's
    /// heart-rate figures. Computed per call; the history is a few dozen rows.
    func runTarget(for kind: RunKind, asOf date: Date = .now, in context: ModelContext) -> RunTarget {
        let running = Modality.running.rawValue
        let completed = SessionStatus.completed.rawValue
        let runs = (try? context.fetch(FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.modalityRaw == running && $0.statusRaw == completed }))) ?? []
        let vdot = RunPacing.fitness(from: runs.compactMap(\.runEffort), asOf: date)
        return RunPacing.target(for: kind, vdot: vdot, zones: profile(in: context).heartRateZones)
    }
}
