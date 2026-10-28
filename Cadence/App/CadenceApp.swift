import SwiftData
import SwiftUI

@main
struct CadenceApp: App {
    let container: ModelContainer
    @State private var coordinator = PlanCoordinator()
    @State private var health: HealthKitService
    @State private var rest: RestTimerService
    @State private var live: LiveWorkoutService

    init() {
        let health = HealthKitService()
        let rest = RestTimerService()
        _health = State(initialValue: health)
        _rest = State(initialValue: rest)
        // Created at launch so a workout the watch starts mirrors here even when the app was not running.
        _live = State(initialValue: LiveWorkoutService(health: health, rest: rest))
        let schema = Schema([AthleteProfile.self, TrainingSession.self, PlannedExercise.self, SetRecord.self, ForecastDay.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Cadence store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(health)
                .environment(rest)
                .environment(live)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .modelContainer(container)
    }
}
