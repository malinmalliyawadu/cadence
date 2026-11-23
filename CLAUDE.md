# Cadence

Native iOS training planner for one athlete who lifts (upper/lower split, four times a week
with a focus area per session), runs, and does hot yoga. Plans the week around training load
and the weather, generates every strength session, and progresses load from reps in reserve.

## Layout

- `Packages/TrainingEngine` - pure Swift, Foundation only, all the maths. `swift test` runs
  133 tests in under a second. Everything that decides what to train lives here, never in views.
  - `Strength/Progression.swift` - RIR-driven load prescription (see below).
  - `Strength/WorkoutGenerator.swift` - six-slot session builder with focus, antagonist and balance slots, plus the
    movements the athlete always wants in an upper or lower session (Settings, In every session).
  - `Strength/SwapRanking.swift` - orders replacements for a movement: same muscle and pattern, then the focus, then familiarity.
  - `Strength/StrengthWorkoutRecord.swift` - a finished session as a Health workout: span from the logged sets, active energy from MET by session RPE.
  - `Strength/WarmUp.swift` - the warm-up ramp before a movement's working sets, modelled on the athlete's own log
    (one set of 8 at 60%, plus 3 at 85% from 100 kg; none for raises, calves, forearms, core, hip ab/adduction,
    dumbbell isolation or bodyweight). The real-export smoke test checks it agrees with what was actually warmed up for.
  - `Strength/RestTimer.swift` - rest between sets by role and rep range (the planner's session minutes use the same
    numbers), and the wall-clock countdown the app, the Live Activity and the notification all read.
  - `Strength/ExerciseTrend.swift` - a movement over time: one point per session (e1RM with bodyweight for bodyweight
    movements, top set, volume), bests, and a window's change and direction from a least-squares slope (half a percent
    of the mean a week).
  - `Strength/SchemePresets.swift` - per-session scheme switches (Heavy, Strength, Hypertrophy, Volume, Pump) and the weight for a new rep range from the latest e1RM, deload kept.
  - `Load/TrainingLoad.swift` - session-RPE load, EWMA acute:chronic ratio, monotony, strain, readiness.
  - `Load/Recovery.swift` - today's recovery from HRV, resting heart rate and sleep against the athlete's own baselines.
  - `Planning/WeekPlanner.swift` - weekly load budget, then exhaustive scored search over day assignments.
  - `Planning/Weather.swift` - running score from a daily forecast (weighted geometric mean).
  - `Running/RunTargets.swift` - target pace from recent runs (Daniels VDOT, best run of eight weeks) and heart-rate zones (Karvonen when resting HR is known).
  - `Running/RacePrediction.swift` - predicted 5 km, 10 km, half and marathon times from that fitness (Daniels' curves
    solved for time), a race goal (5 or 10 km) with its gap, progress since it was set and a projected date from the
    twelve-week trend, and the quality-run rotation a goal brings (intervals, threshold, speed reps, one a week),
    each sized to the run's planned minutes.
  - `Import/WorkoutExportParser.swift` + `Exercises/ExerciseAliases.swift` - CSV import and name mapping.
- `Cadence/` - the app. SwiftUI, SwiftData, Swift Charts, HealthKit, CoreLocation, MapKit (reverse geocoding). iOS 26+.
  - `Features/History/` - the History tab: finished sessions by month (filter by modality, search by movement), and every
    movement lifted with its estimated max and three-month change. A movement opens onto its trend (estimated max, heaviest
    set or volume over a window, drag to read a session), its bests, next time's load and every session it was logged in,
    under how it moves. In a session, History on a movement's Sets header opens the same screen as a sheet with the
    trend and sessions first and how it moves last (`ExerciseDetailSheet(historyFirst:)`).
    The maths is `Strength/ExerciseTrend.swift`; `MovementHistory` lines its points up with the sessions they came from,
    and `HistoryReader` works it out on a background context, since reading every logged set on the main one stalls taps.
  - `Features/Running/` - Race times on Home (predictions against the goal) and its explainer, and how a quality
    run's workout reads. The goal is set in Settings, Race goal (`Features/Settings/RaceGoalSection.swift`).
  - `Features/Home/ExplainerSheet.swift` - what tapping Training load, Recovery, Monotony or Strain on Home slides up:
    the number, a chart of the athlete's own data behind it, the sum with today's values, and what the planner does with it.
  - `Services/PlanCoordinator.swift` - bridges the store and the engine; the only place that persists plans.
  - `Services/HealthKitService.swift` - runs, yoga and strength workouts from Apple Health, effort from Workout Effort Score,
    and HRV, resting heart rate and sleep for recovery;
    saves finished strength sessions back as Traditional Strength Training workouts with the rated effort as their Workout Effort Score.
  - `Services/ImportService.swift` - CSV import, from Settings (Import), the empty week, and the DEBUG `-importCSV <path>`
    launch argument. It adds, never duplicates: a day that already has a completed run or a lift with logged sets is
    left alone, and planned, skipped or setless sessions on an imported day are replaced (a watch workout linked to a
    replaced lift moves to the import). "Replace existing history" (`-importReplace` at launch) wipes every session
    first. Imports are never written to Health. Apple Health is the source for runs, yoga and bodyweight.
  - `Services/RestTimerService.swift` - logging a set starts the rest before the next one: a card on the session screen,
    a Live Activity (Lock Screen and Dynamic Island) and a "Rest over" notification, asked for on the first rest.
    Reads the activity back when the app comes to the front, since its +30 s and Skip buttons work in the background.
  - `Services/SoundEffects.swift` - a soft tick when a set is logged and a chime when rest is over, played ambient (under
    the athlete's music, silent with the ring switch) and off with Settings, Sounds. The rest-over notification rings the
    same chime in the background. `Resources/Sounds` is synthesised by `scripts/generate_sounds.py`: edit the script and
    rerun it, never the files.
  - `Services/LiveWorkoutService.swift` - the watch's live workout, mirrored to the phone. Logging the first set launches
    the watch app with a strength workout; one started on the watch links to today's session. It shows live bpm and
    kcal on the session screen, sends the watch the next set and the rest (the watch taps the wrist, so the phone's
    "Rest over" alert stays quiet meanwhile), and tells it to save on Finish or discard on Skip. No watch, no change.
  - `Services/WeatherService.swift` - Apple Weather (WeatherKit) behind `ForecastProviding`. Debug builds fall back to
    Open-Meteo, since an ad hoc signed simulator build cannot authenticate with WeatherKit; release builds never use
    it (its free API is non-commercial). `Design/WeatherAttribution.swift` is the Apple Weather mark and legal link,
    required wherever forecast data shows (Home, Settings, Credits).
  - `Design/` - palette, type, surfaces (cards, chips, buttons) and the ring and hatched-bar chart pieces.
  - `Design/Typography.swift` - Sora (`Resources/Fonts/Sora.ttf`, a variable font under the OFL, credited in Settings,
    Credits), bundled in the app, the watch app and the widget extension and listed in each target's `UIAppFonts`.
    Text takes `Font.cadence(size:weight:)` or a named style, never `Font.system`, which is kept for SF Symbols.
    Navigation titles and tab labels are UIKit, so `CadenceApp` sets them through the appearance proxies.
  - `Design/Motion.swift` - the four springs everything moves with (press, settle, reveal, exit; critically damped,
    exits a third quicker) and the reveal and rise transitions. `Design/SessionZoom.swift` is the zoom that opens a
    session out of the card or row tapped (kept apart so the watch can compile `Motion` and `Charts`).
  - `Design/MovementArt.swift` - muscle map, movement photos and list thumbnails. The `Movement` and `BodyMap`
    asset groups are generated by `scripts/generate_movement_art.py` (Free Exercise DB photos, public domain;
    react-native-body-highlighter figures, MIT): edit the script's mapping and rerun it, never the assets.
    A movement gets photos only if they show it as programmed. Credits live in Settings, Credits.
  - `Resources/AppIcon.icon` - the app icon, an Icon Composer document the watch app shares: an open violet C with a
    mint dot for today, on indigo, the palette the app takes its colours from. Solid fills; the depth is Liquid Glass.
    Generated by `scripts/generate_app_icon.py`: edit the script and rerun it, never the document. `--preview <dir>`
    renders every appearance with the `ictool` inside Xcode's Icon Composer. Shapes are filled outlines, not strokes:
    Liquid Glass lights the chord that closes an open stroked arc.
- `CadenceWidgets/` - the widget extension, which draws the rest Live Activity. It compiles `Shared/` (the activity's
  attributes and its button intents, also in the app) and the app's `Palette` and `Typography`.
- `CadenceWatch/` - the watchOS 26 app, embedded in the iPhone app. `WorkoutManager` runs an `HKWorkoutSession` with a
  live builder, which is what makes the watch read heart rate every few seconds and work out active energy from it,
  and mirrors it to the phone. Three pages, as in the Workout app: controls (End, Pause) to the left; the workout in
  the middle, a status line (elapsed, bpm, kcal) over the rest countdown or the set to lift; Now Playing to the right.
  The rest is the app's `ProgressRing` without its dial (the track, the violet arc, the mint head), the countdown in
  it, +30 s and Skip as small glass circles in the corners the ring leaves. The set sits low: the movement, a pip per
  set with this one lit, then the load and reps as the largest type the watch draws, from the set's parts (`LiveSet`
  carries number, count, weight and reps as optionals, so an older phone's message falls back to its labels). The
  summary charts heart rate through the session with the rests shaded. Buttons are the system's Liquid Glass
  (`.glass`, `.glassProminent` tinted violet for the one action), and every page keeps a 10 point side gutter.
  It compiles `Shared/LiveWorkout.swift` (the messages both sides send over the mirrored session) and the app's
  `Charts`, `Formatters`, `Motion`, `Palette` and `Typography`. DEBUG `-demoWorkout` starts a workout fed with what the phone would send
  (`-demoRest`, `-demoRestOver` add a rest; `-demoSummary` shows a made-up session's summary and records nothing), since mirroring does not work between simulators: paired simulators
  launch the watch app and record a workout with synthetic heart rate, but the mirrored session reports the phone
  unreachable. Check the live link on real devices.
- `project.yml` - XcodeGen spec. `Cadence.xcodeproj` is generated and git-ignored: run `xcodegen generate` after cloning or editing the spec.

## Build and run

```bash
xcodegen generate
xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build
cd Packages/TrainingEngine && swift test
```

Sign ad hoc (`CODE_SIGN_IDENTITY="-"`), not `CODE_SIGNING_ALLOWED=NO`: the latter drops the
HealthKit entitlement and Health access fails with "Missing com.apple.developer.healthkit entitlement".
Health access reads workouts, effort, active energy, heart rate, HRV, sleep and bodyweight, and writes only strength
workouts, their active energy and their Workout Effort Score. The watch app writes the workouts it records. The simulator has no Fitness app, so to exercise the sync there you
have to write workouts into Health yourself (a throwaway HKWorkoutBuilder call); the app no
longer ships a sample-workout writer. On the Health Access sheet the simulator logs a non-fatal
EXC_GUARD "user fault" from BoardServices and draws a blank frame for a moment; the app survives.
TestFlight: `scripts/testflight.sh` generates the project, archives (team WDB2HN7DW7, build number from the time) and
uploads via `ExportOptions.plist` (method app-store-connect, destination upload); `--no-upload` exports an .ipa to
`build/export` instead. Needs the App Store Connect app record for `nz.malin.cadence.fitness`.
Store listing copy is `AppStore/listing.md`. The privacy, support and marketing pages are `site/`, published from the
public repo malinmalliyawadu/cadence-site with GitHub Pages: copy changes there and push.
Seed the simulator from a real export: `xcrun simctl launch <udid> nz.malin.cadence.fitness -importCSV /path/export.csv`.
Run the parser over a real file: `CADENCE_EXPORT=~/Downloads/WorkoutExport.csv swift test --filter RealExport`.

## The training model, and why

- **Progression is continuous, not "add 2.5 kg when you hit 3x8".** RIR is asked once per
  movement, on the final set (closest to failure, so the most honest, and the set the target
  refers to). That set yields an estimated 1RM via Epley with RIR folded in as unperformed reps.
  The next prescription is the load that puts the bottom of the rep range at the target RIR.
  Where several sets are rated (older logs) the median is used; where none are (imports, or the
  athlete stopped early) the last working set is assumed to land on the target. Jumps are capped at two increments.
  Three sessions without e1RM growth trigger a 10% deload. Bodyweight movements progress on
  bodyweight plus added load, so dips and pull-ups are not stuck at "0 kg".
- **One load scale for everything.** Session RPE times minutes (Foster). Every session takes the
  athlete's 1 to 10 rating, on Apple's Workout Effort Score scale. Finishing a strength session asks for
  it, starting from mean RIR (8.5 minus RIR, clamped), which is also the fallback for imports and older
  logs; the rating sets load only, RIR still drives progression. Runs and yoga use the athlete's rating,
  or the Apple Health Workout Effort Score. This is what lets a long run trade against a leg day.
- **Recovery trims today, load trims the week.** HRV (7-day mean of log SDNN against the 60 days before,
  plus or minus half an SD), resting heart rate (3 days against 30) and sleep (last night, last three nights)
  score a recovery level. Low or poor recovery takes 5 or 10% off today's lifts: readiness uses the lower of the
  load and recovery multipliers. Sessions are generated a week ahead, so after each Health sync
  `PlanCoordinator.applyRecovery` re-prescribes today's untouched strength session, and only when the multiplier changes.
  A session with a set logged is left alone. A heart rate set by hand stands until the athlete hands it back to Health
  in Settings; a bodyweight entered by hand stands until Health has a reading taken after it.
- **ACWR is exponentially weighted (7 and 28 day), not rolling.** No cliff when a big session
  leaves the window. The display and planning snapshots use yesterday as the reference day until
  something is logged today, otherwise every morning looks like a taper.
- **The planner searches, it does not heuristic.** Weekly target = chronic x 7 x readiness factor
  (1.08 in the sweet spot, 0.95 elevated, 0.85 spike); runs flex in duration to fill the budget
  after lifting and yoga. Then every day assignment is scored: rest day, U/L alternation and
  spacing, lower days away from hard runs, one run a day, weather for runs (long run weighted
  most), yoga on wet days and after legs. Pruning keeps the busiest week around a second in debug.
  When the days left cannot hold everything (a week planned on Thursday), the fewest sessions are
  left out, valued lift over long run over quality run over yoga over easy run against the score,
  and a note says which. Nothing is ever placed on an unavailable or past day.
- **The generator prefers movements the athlete has logged.** Malin's gym is Hammer Strength,
  machines, cables and dumbbells; the textbook barbell opener is only chosen when it is familiar
  or nothing familiar fits. `leg-press` is a compound for this reason.

## Conventions

- Weights are kilograms, per hand for dumbbells, added load for bodyweight movements.
- Dates: the week starts Monday (`PlanCoordinator.calendar`). Day indices in preferences are 0 = Monday.
- Warm-ups are not `SetRecord`s: they are worked out from the first working set's weight (`PlannedExercise.warmUps`),
  ticked off in `warmUpsDone`, and shown only until that first set is logged. They never reach progression, load or Health.
- A `SetRecord` with no `completedAt` is a planned set: the athlete changed that set's weight or reps ahead of time. `PlannedExercise.target(at:)` resolves what a set is planned at.
- `SetRecord.rir` is optional and set only on a movement's final set. Imported sets have none; progression assumes the target and the UI says so. Imports are idempotent via `importKey`.
- Health workouts match by day and modality: complete a planned session, enrich a completed one, else create.
  A workout carrying a session's ID in `HKMetadataKeyExternalUUID` (Cadence's watch app stamps it) matches that session.
  A strength session with sets logged is still in progress: a watch workout links to it but does not complete it.
- Finishing a strength session saves a workout to Health, with the rated effort related to it, unless the watch
  already recorded one that day; then the rating goes on the watch workout. A session the watch app recorded live
  (`recordedLive`, set once the watch app takes the workout, mirrored or not) never saves an estimate on finishing: it
  links the watch's workout if it arrives within 90 seconds, else the next sync links it, and only once it is three hours
  overdue (`StrengthWorkoutRecord.estimateIsDue`) does a sync save the estimate. Cadence's own
  workouts are never read back (the watch app's are, as watch workouts); a watch workout that arrives later replaces
  Cadence's copy and takes its rating, and reopening takes back the workout or the rating.
- No em dashes anywhere in copy. Sentence case. Words say what happens ("Log set 3 of 4").
- Design: the app icon's colours. True black canvas, flat cards in a trace of the icon's indigo with no edge or
  outline, active or not (Malin dislikes borders round cards, and finds gradients anywhere tacky). The icon's violet
  is the one accent for whatever is active (the session to start, the movement being logged, the one primary button,
  its label in the icon's indigo), and the icon's mint dot is for today alone (today's bar and day label, the head of
  a progress ring). Every control is Liquid Glass: toolbar and section-header menus, segmented pickers
  (one glass track, the violet sliding), secondary buttons, steppers, option rows and tiles, and the floating rest card.
  The one primary button is glass tinted with the violet. Cards that open something stay flat cards.
  "Change" opens a sheet (`Features/Workout/ChangeSheets.swift`) rather than a menu: focus tiles, run types, and the
  week's other days as rows. Outlined chips for facts, a progress ring as the hero on run and yoga screens, hatched bars for
  weekly load, the icon's mark (`OrbitMark`) on the empty week. Sora throughout, words at medium weight, numbers semibold monospaced.
  Running and yoga use sky and orchid, either side of the violet, only where charts need to tell modalities apart.
  Weight and reps take keyboard entry as well as the steppers. Side margins are `Metrics.gutter` (16), in line with
  the large title. Chips wrap (`ChipFlow`); nothing on a page scrolls sideways. Motion only says where something came
  from, that a tap landed, or that a value changed: no entrance animations on screens seen many times a day.
