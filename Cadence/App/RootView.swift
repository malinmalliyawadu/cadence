import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(HealthKitService.self) private var health
    @Environment(RestTimerService.self) private var rest
    @Environment(LiveWorkoutService.self) private var live
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .home

    enum Tab: Hashable { case home, week, history }

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView()
            }
            SwiftUI.Tab("Week", systemImage: "calendar", value: .week) {
                WeekView()
            }
            SwiftUI.Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", value: .history) {
                HistoryView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            rest.sync()
            live.attach(context: context, coordinator: coordinator)
            _ = coordinator.profile(in: context)
            await importFromLaunchArguments()
            await coordinator.refreshForecast(in: context)
            await health.sync(in: context, coordinator: coordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            rest.sync()
            guard health.isEnabled else { return }
            Task { await health.sync(in: context, coordinator: coordinator) }
        }
    }

    /// Development convenience: `-importCSV /path/to/export.csv` adds an export's history on
    /// launch, for seeding a simulator. `-importReplace` wipes every session first.
    private func importFromLaunchArguments() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-importCSV"), index + 1 < arguments.count else { return }
        let url = URL(fileURLWithPath: arguments[index + 1])
        do {
            let summary = try await ImportService.importExport(at: url, replacingExisting: arguments.contains("-importReplace"), in: context, coordinator: coordinator)
            print("Imported \(url.lastPathComponent): \(summary.message)")
            await coordinator.planWeek(in: context)
        } catch {
            print("Import of \(url.path) failed: \(error.localizedDescription)")
        }
        #endif
    }
}
