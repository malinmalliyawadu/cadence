import SwiftData
import SwiftUI

@main
struct CadenceApp: App {
    let container: ModelContainer
    @State private var coordinator = PlanCoordinator()
    @State private var health = HealthKitService()

    init() {
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
                .preferredColorScheme(.dark)
                .tint(Palette.ember)
        }
        .modelContainer(container)
    }
}
