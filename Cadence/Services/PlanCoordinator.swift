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

        // 1. Clear this week's untouched sessions.
        let weekSessions = sessions(weekStart: start, in: context)
        for session in weekSessions where session.status == .planned && session.date >= today {
            context.delete(session)
        }
        let kept = weekSessions.filter { !($0.status == .planned && $0.date >= today) }

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
                bodyweightKg: profile.bodyweightKg
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

    /// Marks a session done. Strength sessions derive their RPE from the logged RIR and
    /// advance the focus rotation so the next plan picks up where this one left off.
    func complete(_ session: TrainingSession, minutes: Double? = nil, rpe: Double? = nil, distanceKm: Double? = nil, in context: ModelContext) {
        session.status = .completed
        session.completedAt = .now
        session.actualMinutes = minutes ?? session.plannedMinutes
        if let rpe { session.rpe = rpe }
        if let distanceKm { session.distanceKm = distanceKm }
        if session.modality == .strength {
            session.rpe = TrainingLoad.strengthSessionRPE(meanRIR: session.loggedMeanRIR ?? session.meanTargetRIR)
            let profile = profile(in: context)
            if let focus = session.focus {
                if focus.half == .upper { profile.nextUpperFocus = focus.next } else { profile.nextLowerFocus = focus.next }
            }
        }
        try? context.save()
    }

    func skip(_ session: TrainingSession, in context: ModelContext) {
        session.status = .skipped
        try? context.save()
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
        let snapshot = LoadAnalysis.snapshot(entries: loadEntries(in: context), planningOn: session.date, calendar: calendar)
        let readiness = Readiness.from(snapshot)
        let recent = Set(lastCompletedStrength(half: half, in: context)?.exercises.map(\.exerciseID) ?? [])
        let generated = WorkoutGenerator.generate(StrengthSessionRequest(
            half: half,
            focus: focus,
            availableEquipment: profile.equipment,
            recentExerciseIDs: recent,
            history: history(in: context),
            readiness: readiness.loadMultiplier,
            setReduction: readiness.setReduction,
            variationSeed: Int(session.date.timeIntervalSince1970 / 86_400),
            bodyweightKg: profile.bodyweightKg
        ))
        for exercise in session.exercises { context.delete(exercise) }
        session.exercises = generated.prescriptions.enumerated().map { PlannedExercise(prescription: $1, order: $0) }
        session.half = half
        session.focus = focus
        session.plannedMinutes = generated.estimatedMinutes.rounded()
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

    /// Swaps a movement for another of the same role that trains the same primary muscle.
    func swap(_ exercise: PlannedExercise, in context: ModelContext) {
        guard let current = exercise.exercise, let session = exercise.session else { return }
        let profile = profile(in: context)
        let used = Set(session.exercises.map(\.exerciseID))
        let candidates = ExerciseLibrary.exercises(for: current.half).filter {
            $0.role == current.role && $0.primary == current.primary && !used.contains($0.id) && profile.equipment.contains($0.equipment)
        }
        guard let replacement = candidates.first else { return }
        let result = Progression.nextLoad(for: replacement, history: history(in: context), repRange: exercise.repRange, targetRIR: exercise.targetRIR, bodyweightKg: profile.bodyweightKg)
        exercise.exerciseID = replacement.id
        exercise.prescribedWeightKg = result.weightKg
        exercise.rationale = result.rationale
        for set in exercise.sets { context.delete(set) }
        exercise.sets = []
        try? context.save()
    }
}
