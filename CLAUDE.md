# Cadence

Native iOS training planner for one athlete who lifts (upper/lower split, four times a week
with a focus area per session), runs, and does hot yoga. Plans the week around training load
and the weather, generates every strength session, and progresses load from reps in reserve.

## Layout

- `Packages/TrainingEngine` - pure Swift, Foundation only, all the maths. `swift test` runs
  50 tests in under a second. Everything that decides what to train lives here, never in views.
  - `Strength/Progression.swift` - RIR-driven load prescription (see below).
  - `Strength/WorkoutGenerator.swift` - six-slot session builder with focus, antagonist and balance slots.
  - `Load/TrainingLoad.swift` - session-RPE load, EWMA acute:chronic ratio, monotony, strain, readiness.
  - `Planning/WeekPlanner.swift` - weekly load budget, then exhaustive scored search over day assignments.
  - `Planning/Weather.swift` - running score from a daily forecast (weighted geometric mean).
  - `Import/WorkoutExportParser.swift` + `Exercises/ExerciseAliases.swift` - CSV import and name mapping.
- `Cadence/` - the app. SwiftUI, SwiftData, Swift Charts, HealthKit, CoreLocation. iOS 26+, Liquid Glass.
  - `Services/PlanCoordinator.swift` - bridges the store and the engine; the only place that persists plans.
  - `Services/HealthKitService.swift` - runs and yoga from Apple Health, effort from Workout Effort Score.
  - `Services/ImportService.swift` - DEBUG only. `-importCSV <path>` launch argument seeds a simulator with real history. There is no import UI by Malin's request; Apple Health is the source for runs, yoga and bodyweight.
  - `Services/WeatherService.swift` - Open-Meteo, no key. Swap via `ForecastProviding`.
  - `Design/` - palette, type, the mesh-gradient backdrop and glass helpers.
- `project.yml` - XcodeGen spec. `Cadence.xcodeproj` is generated and git-ignored: run `xcodegen generate` after cloning or editing the spec.

## Build and run

```bash
xcodegen generate
xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build
cd Packages/TrainingEngine && swift test
```

Sign ad hoc (`CODE_SIGN_IDENTITY="-"`), not `CODE_SIGNING_ALLOWED=NO`: the latter drops the
HealthKit entitlement and Health access fails with "Missing com.apple.developer.healthkit entitlement".
Health access is read only. The simulator has no Fitness app, so to exercise the sync there you
have to write workouts into Health yourself (a throwaway HKWorkoutBuilder call); the app no
longer ships a sample-workout writer. On the Health Access sheet the simulator logs a non-fatal
EXC_GUARD "user fault" from BoardServices and draws a blank frame for a moment; the app survives.
Seed the simulator from a real export: `xcrun simctl launch <udid> nz.malin.cadence -importCSV /path/export.csv`.
Run the parser over a real file: `CADENCE_EXPORT=~/Downloads/WorkoutExport.csv swift test --filter RealExport`.

## The training model, and why

- **Progression is continuous, not "add 2.5 kg when you hit 3x8".** Each working set yields an
  estimated 1RM via Epley with RIR folded in as unperformed reps. The next prescription is the
  load that puts the bottom of the rep range at the target RIR. The session e1RM is the median
  working set, so one optimistic RIR cannot drive next week. Jumps are capped at two increments.
  Three sessions without e1RM growth trigger a 10% deload. Bodyweight movements progress on
  bodyweight plus added load, so dips and pull-ups are not stuck at "0 kg".
- **One load scale for everything.** Session RPE times minutes (Foster). Strength RPE is derived
  from mean RIR (8.5 minus RIR, clamped). Runs and yoga use the athlete's rating, or the Apple
  Health Workout Effort Score. This is what lets a long run trade against a leg day.
- **ACWR is exponentially weighted (7 and 28 day), not rolling.** No cliff when a big session
  leaves the window. The display and planning snapshots use yesterday as the reference day until
  something is logged today, otherwise every morning looks like a taper.
- **The planner searches, it does not heuristic.** Weekly target = chronic x 7 x readiness factor
  (1.08 in the sweet spot, 0.95 elevated, 0.85 spike); runs flex in duration to fill the budget
  after lifting and yoga. Then every day assignment is scored: rest day, U/L alternation and
  spacing, lower days away from hard runs, one run a day, weather for runs (long run weighted
  most), yoga on wet days and after legs. Pruning keeps the busiest week around a second in debug.
- **The generator prefers movements the athlete has logged.** Malin's gym is Hammer Strength,
  machines, cables and dumbbells; the textbook barbell opener is only chosen when it is familiar
  or nothing familiar fits. `leg-press` is a compound for this reason.

## Conventions

- Weights are kilograms, per hand for dumbbells, added load for bodyweight movements.
- Dates: the week starts Monday (`PlanCoordinator.calendar`). Day indices in preferences are 0 = Monday.
- Imported sets have no RIR; 2 is assumed and the UI says so. Imports are idempotent via `importKey`.
- Health workouts match by day and modality: complete a planned session, enrich a completed one, else create.
- No em dashes anywhere in copy. Sentence case. Words say what happens ("Log set 3 of 4").
- Design: glass only on things you can act on; one bold element per screen; three modality hues
  (ember, sky, heat) carry the identity; numbers in rounded monospaced digits.
