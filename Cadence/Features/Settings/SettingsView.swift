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
    @State private var syncing = false
    @State private var showImporter = false
    @State private var replaceOnImport = false
    @State private var importing = false
    @State private var importMessage: String?
    @AppStorage(SoundEffects.enabledKey) private var soundsEnabled = true

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
        .presentationBackground(Palette.canvas)
    }

    @ViewBuilder
    private func form(for profile: AthleteProfile) -> some View {
        @Bindable var profile = profile
        Form {
            Group {
                Section {
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
                } header: {
                    Text("Week").formHeader()
                }

                RaceGoalSection(profile: profile)

                Section {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            let off = profile.unavailableDays.contains(index)
                            Button(dayNames[index]) {
                                if off { profile.unavailableDays.removeAll { $0 == index } } else { profile.unavailableDays.append(index) }
                            }
                            .font(.cadence(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(off ? Palette.inkTertiary : Palette.onAccent)
                            .contentShape(.capsule)
                            .glassEffect(off ? .regular.interactive() : .regular.tint(Palette.accent).interactive(), in: .capsule)
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(dayNames[index]) \(off ? "unavailable" : "available")")
                        }
                    }
                } header: {
                    Text("Days you can train").formHeader()
                } footer: {
                    Text("Tap a day to mark it off. The planner never schedules on grey days.").formFooter()
                }

                Section {
                    Picker("Upper", selection: $profile.nextUpperFocus) {
                        ForEach(FocusArea.areas(for: .upper)) { Text($0.displayName).tag($0) }
                    }
                    Picker("Lower", selection: $profile.nextLowerFocus) {
                        ForEach(FocusArea.areas(for: .lower)) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Next focus").formHeader()
                }

                Section {
                    ForEach(BodyHalf.allCases, id: \.self) { half in
                        NavigationLink { AlwaysIncludedView(half: half) } label: {
                            LabeledContent(half.displayName, value: alwaysIncludedSummary(profile.alwaysIncluded(for: half)))
                        }
                    }
                } header: {
                    Text("In every session").formHeader()
                } footer: {
                    Text("Added on top of the six movements the planner picks. Upcoming sessions with nothing logged change too.").formFooter()
                }

                Section {
                    ForEach(Equipment.allCases, id: \.self) { item in
                        Toggle(item.rawValue.capitalized, isOn: Binding(
                            get: { profile.equipment.contains(item) },
                            set: { on in var set = profile.equipment; if on { set.insert(item) } else { set.remove(item) }; profile.equipment = set }
                        ))
                    }
                } header: {
                    Text("Equipment").formHeader()
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
                        Text("Location is off for Cadence. Turn it on in Settings, or keep the default.").font(.footnote2).foregroundStyle(.secondary)
                    }
                    if case .failed(let message) = location.state {
                        Text(message).font(.footnote2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Forecast").formHeader()
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Forecasts come from Apple Weather for the ten days ahead. Runs chase mild, dry, still days.").formFooter()
                        WeatherAttributionView()
                    }
                }

                Section {
                    // A manual nudge is a manual value until Health has a reading taken after it.
                    Stepper("Bodyweight: \(Format.kg(profile.bodyweightKg)) kg", value: Binding(get: { profile.bodyweightKg }, set: {
                        profile.bodyweightKg = $0
                        profile.bodyweightFromHealthAt = nil
                        profile.bodyweightEnteredAt = .now
                    }), in: 40...200, step: 0.5)
                } header: {
                    Text("Body").formHeader()
                } footer: {
                    Group {
                        if let date = profile.bodyweightFromHealthAt {
                            Text("From Apple Health, \(date.formatted(date: .abbreviated, time: .omitted)). Used to progress dips, pull-ups and chin-ups.")
                        } else {
                            Text(health.isEnabled
                                 ? "Used to progress dips, pull-ups and chin-ups."
                                 : "Used to progress dips, pull-ups and chin-ups. Connect Apple Health to keep it current.")
                        }
                    }
                    .formFooter()
                }

                Section {
                    Stepper(value: Binding(get: { profile.maxHeartRate ?? 185 }, set: { profile.maxHeartRate = $0; profile.maxHeartRateSetByHand = true }), in: 120...220) {
                        LabeledContent("Max heart rate", value: profile.maxHeartRate.map { "\($0) bpm" } ?? "Not set")
                    }
                    Stepper(value: Binding(get: { profile.restingHeartRate ?? 55 }, set: { profile.restingHeartRate = $0; profile.restingHeartRateSetByHand = true }), in: 30...100) {
                        LabeledContent("Resting heart rate", value: profile.restingHeartRate.map { "\($0) bpm" } ?? "Not set")
                    }
                    if health.isEnabled, profile.maxHeartRateSetByHand || profile.restingHeartRateSetByHand {
                        Button("Use Apple Health") {
                            profile.maxHeartRateSetByHand = false
                            profile.restingHeartRateSetByHand = false
                            syncing = true
                            Task {
                                await health.sync(in: context, coordinator: coordinator)
                                syncing = false
                            }
                        }
                        .disabled(syncing)
                    }
                } header: {
                    Text("Heart rate").formHeader()
                } footer: {
                    Group {
                        if profile.maxHeartRateSetByHand || profile.restingHeartRateSetByHand {
                            Text(heartRateByHandNote(max: profile.maxHeartRateSetByHand, resting: profile.restingHeartRateSetByHand, healthEnabled: health.isEnabled))
                        } else if let date = profile.heartRateFromHealthAt {
                            Text("From Apple Health, \(date.formatted(date: .abbreviated, time: .omitted)). Sets the heart-rate zones for runs; resting rate makes them fit you more closely.")
                        } else {
                            Text(health.isEnabled
                                 ? "Sets the heart-rate zones for runs. These fill in from your watch once Apple Health has heart-rate readings."
                                 : "Sets the heart-rate zones for runs. Connect Apple Health and these fill in from your watch.")
                        }
                    }
                    .formFooter()
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
                        Text(message).font(.footnote2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health").formHeader()
                } footer: {
                    Text("Runs, hot yoga and strength workouts logged in Fitness complete the matching planned session, with duration, distance and your Workout Effort Score as the effort rating. Finished strength sessions are saved to Apple Health with the effort you rate; if your watch recorded the session, the rating goes on its workout instead. With Cadence on your Apple Watch, logging your first set starts a workout there, so heart rate and calories are measured as you lift. HRV, resting heart rate and sleep set the day's recovery. Syncs whenever Cadence opens.").formFooter()
                }

                Section {
                    Toggle("Set and rest sounds", isOn: $soundsEnabled)
                } header: {
                    Text("Sounds").formHeader()
                } footer: {
                    Text("A soft tick when you log a set and a chime when rest is over, under whatever you are listening to. Quiet with the ring switch on silent.").formFooter()
                }

                Section {
                    Toggle("Replace existing history", isOn: $replaceOnImport)
                    Button {
                        showImporter = true
                    } label: {
                        HStack {
                            Label("Import a workout export", systemImage: "square.and.arrow.down")
                            Spacer()
                            if importing { ProgressView() }
                        }
                    }
                    .disabled(importing)
                } header: {
                    Text("Import").formHeader()
                } footer: {
                    // The result sits in the footer: inserting a row under the button leaves a seam.
                    VStack(alignment: .leading, spacing: 8) {
                        if let importMessage {
                            Text(importMessage).foregroundStyle(Palette.ink)
                        }
                        Text(replaceOnImport
                             ? "Deletes every session, logged and planned, then imports the file. Reps in reserve are assumed to be 2 for imported sets."
                             : "Adds lifts and runs from a CSV with Date, Exercise, Reps, Weight(kg), Duration(s), Distance(m) and isWarmup columns. Days already in Cadence are left alone, so importing again only adds what is new. Reps in reserve are assumed to be 2 for imported sets.")
                    }
                    .formFooter()
                }

                Section {
                    NavigationLink("Credits") { CreditsView() }
                }

                Section {
                    Button("Delete all sessions", role: .destructive) { confirmWipe = true }
                        // On the button, so the dialog points at what opened it.
                        .confirmationDialog("Delete every session?", isPresented: $confirmWipe, titleVisibility: .visible) {
                            Button("Delete all sessions", role: .destructive) { coordinator.deleteAllSessions(in: context) }
                        } message: {
                            Text("This removes all history and plans. Settings stay.")
                        }
                } footer: {
                    Text("Cadence \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").formFooter()
                }
            }
            .listRowBackground(Palette.surface)
        }
        // Sora runs wider than SF, so rows sit a point under the system's 17 to leave their controls room.
        .font(.cadence(size: 16))
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
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
            importing = true
            Task {
                importMessage = await ImportService.importPicked(result, replacingExisting: replaceOnImport, in: context, coordinator: coordinator)
                importing = false
            }
        }
    }

    private func heartRateByHandNote(max: Bool, resting: Bool, healthEnabled: Bool) -> String {
        let what = max && resting ? "Both are" : max ? "Max is" : "Resting is"
        let kept = healthEnabled ? " Apple Health leaves \(max && resting ? "them" : "it") alone." : ""
        return "Sets the heart-rate zones for runs. \(what) set by hand.\(kept)"
    }

    private func alwaysIncludedSummary(_ ids: [String]) -> String {
        let names = ids.compactMap { ExerciseLibrary.exercise(id: $0)?.name }
        switch names.count {
        case 0: return "None"
        case 1: return names[0]
        default: return "\(names.count) movements"
        }
    }
}

/// A form's section headers and footers as the system draws them, in Sora: an explicit font
/// replaces the system's header and footer styles, so each one names its own.
extension View {
    func formHeader() -> some View { font(.cadence(size: 16, weight: .semibold)) }
    func formFooter() -> some View { font(.footnote2) }
}
