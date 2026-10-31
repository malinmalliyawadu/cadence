import SwiftUI
import TrainingEngine

/// The acute:chronic ratio as one number, what it means for the week, and where it sits on the
/// zones the planner reads: under-reaching, the sweet spot, elevated, spike. Under it, once Apple
/// Health has been read, today's recovery: HRV, resting heart rate and sleep against their usual.
struct ReadinessCard: View {
    let snapshot: LoadSnapshot
    var recovery: RecoveryStatus?
    var lifting: RecoveryStatus.TodaysLifting = .none
    /// Opens the explainer for the section tapped.
    var onExplain: (Explainer) -> Void = { _ in }

    private var readiness: Readiness { Readiness.from(snapshot) }

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Button { onExplain(.trainingLoad) } label: { load }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Explains training load")
                if let recovery {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    Button { onExplain(.recovery) } label: { RecoverySection(recovery: recovery, lifting: lifting) }
                        .buttonStyle(.pressable)
                        .accessibilityHint("Explains recovery")
                }
            }
        }
    }

    private var load: some View {
        let zone = readiness.zone
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TitleIcon(symbol: zone.symbolName, tint: zone.tint)
                Text("Training load").font(.rowTitle).foregroundStyle(Palette.ink)
                InfoGlyph()
                Spacer(minLength: 8)
                StatusChip(text: zone.displayName, tint: zone.tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.ratio(snapshot.acwr))
                    .font(.numeralLarge)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("acute to chronic")
                    .font(.body2)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Text(readiness.headline)
                .font(.body2)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ZoneGauge(acwr: snapshot.acwr)
            HStack(spacing: 0) {
                figure("Acute, 7 day", snapshot.today.map { Format.load($0.acute) })
                figure("Chronic, 28 day", snapshot.today.map { Format.load($0.chronic) })
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training load, \(zone.displayName)")
        .accessibilityValue("Ratio \(Format.ratio(snapshot.acwr)). \(readiness.headline)")
    }
}

/// Today's recovery: a verdict, what it does to today's lifts, and the three signals behind it.
private struct RecoverySection: View {
    let recovery: RecoveryStatus
    let lifting: RecoveryStatus.TodaysLifting

    var body: some View {
        let tint = recovery.level.map(Palette.color(for:)) ?? Palette.rest
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TitleIcon(symbol: "waveform.path.ecg", tint: tint)
                Text("Recovery").font(.rowTitle).foregroundStyle(Palette.ink)
                InfoGlyph()
                Spacer(minLength: 8)
                StatusChip(text: recovery.level?.displayName ?? "Learning", tint: tint)
            }
            Text(recovery.headline(lifting))
                .font(.body2)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 0) {
                figure("HRV, 7 day", recovery.hrv.map { "\(Int($0.current.rounded())) ms" },
                       usual: recovery.hrv.map { signal in
                           signal.normalRange.map { "Usual \(Int($0.lowerBound.rounded())) to \(Int($0.upperBound.rounded()))" } ?? "Learning your range"
                       },
                       flagged: recovery.hrv?.points ?? 0 > 0)
                figure("Resting", recovery.restingHeartRate.map { "\(Int($0.current.rounded())) bpm" },
                       usual: recovery.restingHeartRate.map { signal in signal.baseline.map { "Usual \(Int($0.rounded()))" } ?? "Learning your usual" },
                       flagged: recovery.restingHeartRate?.points ?? 0 > 0)
                figure("Sleep", recovery.sleep.map { Format.sleep($0.current) },
                       usual: recovery.sleep.map { signal in signal.baseline.map { "Usual \(Format.sleep($0))" } ?? "Last night" },
                       flagged: recovery.sleep?.points ?? 0 > 0)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery, \(recovery.level?.displayName ?? "learning your baseline")")
        .accessibilityValue(recovery.headline(lifting))
    }
}

private func figure(_ title: String, _ value: String?, usual: String? = nil, flagged: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.label).foregroundStyle(Palette.inkTertiary)
        Text(value ?? "–").font(.numeralSmall).foregroundStyle(flagged ? Palette.amber : Palette.ink)
        if let usual {
            Text(usual).font(.label).foregroundStyle(Palette.inkTertiary)
        } else if value == nil {
            Text("No reading").font(.label).foregroundStyle(Palette.inkTertiary)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// A flat track split into the ratio's zones, the current one lit, with a marker at today's ratio.
/// The track is inset by the marker's radius, so the marker stays inside it at either end.
struct ZoneGauge: View {
    let acwr: Double?

    private static let range = 0.4...1.8
    private static let bands: [(ClosedRange<Double>, LoadZone)] = [
        (0.4...0.8, .undertrained), (0.8...1.3, .optimal), (1.3...1.5, .elevated), (1.5...1.8, .danger),
    ]
    private static let ticks = [0.8, 1.3, 1.5]
    private static let marker: CGFloat = 18

    var body: some View {
        let current = LoadZone.zone(for: acwr)
        GeometryReader { proxy in
            let width = proxy.size.width - Self.marker
            ZStack(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(Self.bands, id: \.1) { band, zone in
                        Capsule()
                            .fill(zone.tint.opacity(zone == current ? 1 : 0.22))
                            .frame(width: max(0, (band.upperBound - band.lowerBound) / span * width - 3))
                    }
                }
                .frame(height: 8)
                .offset(x: Self.marker / 2, y: 5)
                if let acwr {
                    Circle()
                        .fill(.white)
                        .overlay { Circle().strokeBorder(Palette.canvas, lineWidth: 3) }
                        .frame(width: Self.marker, height: Self.marker)
                        .offset(x: x(for: acwr, width: width) - Self.marker / 2)
                        .animation(Motion.settle, value: acwr)
                }
                ForEach(Self.ticks, id: \.self) { tick in
                    Text(String(format: "%.1f", tick))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.inkTertiary)
                        .fixedSize()
                        .frame(width: 30)
                        .offset(x: x(for: tick, width: width) - 15, y: 24)
                }
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    private var span: Double { Self.range.upperBound - Self.range.lowerBound }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        return Self.marker / 2 + CGFloat((clamped - Self.range.lowerBound) / span) * width
    }
}
