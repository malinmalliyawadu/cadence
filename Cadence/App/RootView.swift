import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(HealthKitService.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .today

    enum Tab: Hashable { case today, week, load, library }

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "sun.max.fill", value: .today) {
                TodayView()
            }
            SwiftUI.Tab("Week", systemImage: "calendar", value: .week) {
                WeekView()
            }
            SwiftUI.Tab("Load", systemImage: "waveform.path.ecg", value: .load) {
                LoadView()
            }
            SwiftUI.Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                LibraryView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            _ = coordinator.profile(in: context)
            await importFromLaunchArguments()
            await coordinator.refreshForecast(in: context)
            await health.sync(in: context, coordinator: coordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, health.isEnabled else { return }
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
