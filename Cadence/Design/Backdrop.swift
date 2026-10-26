import SwiftUI
import TrainingEngine

/// The living backdrop the glass sits over. A slow mesh gradient whose colours come from
/// the session's modality and the day's forecast: rain pulls the sky toward slate, heat
/// warms the ember, a rest day cools everything down. Drift respects Reduce Motion.
struct AtmosphereBackdrop: View {
    var modality: Modality?
    var forecast: DayForecast?
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 14
            MeshGradient(
                width: 3,
                height: 3,
                points: points(t: t),
                colors: colors,
                smoothsColors: true
            )
            .overlay(grain)
            .ignoresSafeArea()
        }
    }

    private var grain: some View {
        // Fine noise keeps large soft gradients from banding on OLED.
        Rectangle()
            .fill(.white.opacity(0.025))
            .blendMode(.overlay)
    }

    private func points(t: Double) -> [SIMD2<Float>] {
        func drift(_ x: Double, _ y: Double, _ phase: Double, _ amount: Double = 0.12) -> SIMD2<Float> {
            SIMD2(Float(x + sin(t + phase) * amount), Float(y + cos(t * 0.8 + phase) * amount))
        }
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            drift(0.0, 0.5, 0, 0.0), drift(0.5, 0.5, 1.3), drift(1.0, 0.5, 2.1, 0.0),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
    }

    private var colors: [Color] {
        let base = Palette.night
        let accent = modality?.tint ?? Palette.rest
        let rain = forecast?.precipitationProbability ?? 0
        let warm = forecast.map { min(1, max(0, ($0.tempMaxC - 5) / 25)) } ?? 0.5
        let slate = Color(red: 0.16, green: 0.20, blue: 0.28)

        let glow = accent.opacity(0.85 * intensity)
        let secondary: Color = switch modality {
        case .strength: Palette.heat.opacity(0.35 * intensity)
        case .running: slate.opacity(0.4 + rain * 0.5)
        case .yoga: Palette.ember.opacity(0.4 * intensity)
        case nil: slate.opacity(0.5)
        }
        let tertiary: Color = modality == .running
            ? Palette.sky.opacity((0.2 + warm * 0.3) * intensity)
            : accent.opacity(0.25 * intensity)

        return [
            base, secondary, base,
            glow, base.opacity(0.9), tertiary,
            base, accent.opacity(0.18 * intensity), base,
        ]
    }
}

#Preview("Strength") {
    AtmosphereBackdrop(modality: .strength)
}

#Preview("Run, wet") {
    AtmosphereBackdrop(modality: .running, forecast: DayForecast(date: .now, tempMaxC: 11, tempMinC: 6, precipitationProbability: 0.8, precipitationMm: 6, windKph: 30, uvIndex: 2, weatherCode: 61))
}
