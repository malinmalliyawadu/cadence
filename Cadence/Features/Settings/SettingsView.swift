import SwiftData
import SwiftUI
import TrainingEngine
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlanCoordinator.self) private var coordinator
    @Environment(HealthKitService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [AthleteProfile]
    @State private var location = LocationService()
    @State private var confirmWipe = false
    @State private var showImporter = false
    @State private var replaceOnImport = true
    @State private var importMessage: String?
    @State private var syncing = false

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationStack {
            if let profile = profiles.first {
                form(for: profile)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            } else {
                ProgressView().task { _ = coordinator.profile(in: context) }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    @ViewBuilder
    private func form(for profile: AthleteProfile) -> some View {
        @Bindable var profile = profile
        Form {
            Section("Week") {
                Stepper("Strength sessions: \(profile.strengthSessionsPerWeek)", value: $profile.strengthSessionsPerWeek, in: 0...6)
                Toggle("Long run", isOn: $profile.includeLongRun)
                Toggle("Quality run (tempo or intervals)", isOn: $profile.includeQualityRun)
                Stepper("Easy runs: \(profile.easyRuns)", value: $profile.easyRuns, in: 0...4)
                Stepper("Hot yoga classes: \(profile.yogaSessions)", value: $profile.yogaSessions, in: 0...4)
                Toggle("Allow two sessions in a day", isOn: $profile.allowTwoADays)
                Picker("Preferred long run day", selection: Binding(get: { profile.preferredLongRunDay ?? -1 }, set: { profile.preferredLongRunDay = $0 < 0 ? nil : $0 })) {
                    Text("No preference").tag(-1)
                    ForEach(0..<7, id: \.self) { Text(dayNames[$0]).tag($0) }
                }
            }

            Section {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let off = profile.unavailableDays.contains(index)
                        Button(dayNames[index]) {
                            if off { profile.unavailableDays.removeAll { $0 == index } } else { profile.unavailableDays.append(index) }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(off ? Palette.inkTertiary : Palette.ink)
                        .background(off ? Color.clear : Palette.ember.opacity(0.25), in: .capsule)
                        .overlay(Capsule().strokeBorder(Palette.hairline))
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(dayNames[index]) \(off ? "unavailable" : "available")")
                    }
                }
            } header: {
                Text("Days you can train")
            } footer: {
                Text("Tap a day to mark it off. The planner never schedules on grey days.")
            }

            Section("Next focus") {
                Picker("Upper", selection: $profile.nextUpperFocus) {
                    ForEach(FocusArea.areas(for: .upper)) { Text($0.displayName).tag($0) }
                }
                Picker("Lower", selection: $profile.nextLowerFocus) {
                    ForEach(FocusArea.areas(for: .lower)) { Text($0.displayName).tag($0) }
                }
            }

            Section("Equipment") {
                ForEach(Equipment.allCases, id: \.self) { item in
                    Toggle(item.rawValue.capitalized, isOn: Binding(
                        get: { profile.equipment.contains(item) },
                        set: { on in var set = profile.equipment; if on { set.insert(item) } else { set.remove(item) }; profile.equipment = set }
                    ))
                }
            }

            Section {
                LabeledContent("Place", value: profile.locationName)
                Button {
                    location.locate()
                } label: {
                    HStack {
                        Label("Use my location", systemImage: "location.fill")
                        Spacer()
                        if case .requesting = location.state { ProgressView() }
                    }
                }
                if case .denied = location.state {
                    Text("Location is off for Cadence. Turn it on in Settings, or keep the default.").font(.footnote).foregroundStyle(.secondary)
                }
                if case .failed(let message) = location.state {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Forecast")
            } footer: {
                Text("Forecasts come from Open-Meteo for the ten days ahead. Runs chase mild, dry, still days.")
            }

            Section {
                Stepper("Bodyweight: \(Format.kg(profile.bodyweightKg)) kg", value: $profile.bodyweightKg, in: 40...200, step: 0.5)
                    .onChange(of: profile.bodyweightKg) { _, _ in
                        // A manual nudge is a manual value until Health next reports a reading.
                        if profile.bodyweightFromHealthAt != nil, !syncing { profile.bodyweightFromHealthAt = nil }
                    }
            } header: {
                Text("Body")
            } footer: {
                if let date = profile.bodyweightFromHealthAt {
                    Text("From Apple Health, \(date.formatted(date: .abbreviated, time: .omitted)). Used to progress dips, pull-ups and chin-ups.")
                } else {
                    Text("Used to progress dips, pull-ups and chin-ups. Connect Apple Health to keep it current.")
                }
            }

            Section {
                if !health.isAvailable {
                    Text("Apple Health is not available on this device.").foregroundStyle(.secondary)
                } else if health.state == .ready || health.isEnabled {
                    Button {
                        syncing = true
                        Task {
                            await health.sync(in: context, coordinator: coordinator)
                            syncing = false
                        }
                    } label: {
                        HStack {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if syncing { ProgressView() }
                        }
                    }
                    .disabled(syncing)
                    if let lastSync = health.lastSync {
                        LabeledContent("Last sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                    }
                    #if DEBUG
                    Button("Write sample workouts to Health") { Task { await health.writeSampleWorkouts() } }
                    #endif
                } else {
                    Button {
                        Task { await health.requestAccess() }
                    } label: {
                        HStack {
                            Label("Connect Apple Health", systemImage: "heart.fill")
                            Spacer()
                            if health.state == .requesting { ProgressView() }
                        }
                    }
                }
                if let message = health.lastMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Runs and hot yoga logged in Fitness complete the matching planned session, with duration, distance and your Workout Effort Score as the effort rating. Syncs whenever Cadence opens.")
            }

            Section {
                Toggle("Replace existing history", isOn: $replaceOnImport)
                Button {
                    showImporter = true
                } label: {
                    Label("Import a workout export", systemImage: "square.and.arrow.down")
                }
                if let importMessage {
                    Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Import")
            } footer: {
                Text("A CSV with Date, Exercise, Reps, Weight(kg), Duration(s), Distance(m) and isWarmup columns. Reps in reserve are assumed to be 2 for imported sets.")
            }

            Section {
                Button("Replace history with sample data") {
                    SampleData.wipe(in: context)
                    SampleData.seed(in: context, coordinator: coordinator)
                }
                Button("Delete all sessions", role: .destructive) { confirmWipe = true }
            } footer: {
                Text("Cadence \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            }
        }
        .onChange(of: location.state) { _, state in
            if case .located(let fix) = state {
                profile.latitude = fix.latitude
                profile.longitude = fix.longitude
                profile.locationName = fix.name
                profile.usesDeviceLocation = true
                Task { await coordinator.refreshForecast(in: context) }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                do {
                    let summary = try ImportService.importExport(at: url, replacingExisting: replaceOnImport, in: context, coordinator: coordinator)
                    importMessage = summary.message
                    Task { await coordinator.planWeek(in: context) }
                } catch {
                    importMessage = "Could not import: \(error.localizedDescription)"
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Delete every session?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete all sessions", role: .destructive) { SampleData.wipe(in: context) }
        } message: {
            Text("This removes all history and plans. Settings stay.")
        }
    }
}
