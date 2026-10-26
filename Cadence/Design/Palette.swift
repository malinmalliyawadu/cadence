import SwiftUI
import TrainingEngine

/// Semantic colour tokens. Three modality hues carry the whole identity; everything
/// else is white at a few opacities over the night base so glass has room to work.
enum Palette {
    static let night = Color(red: 0.027, green: 0.035, blue: 0.059)
    static let ember = Color(red: 1.0, green: 0.416, blue: 0.239)
    static let sky = Color(red: 0.298, green: 0.788, blue: 0.941)
    static let heat = Color(red: 0.945, green: 0.357, blue: 0.710)
    static let rest = Color(red: 0.55, green: 0.60, blue: 0.70)

    static let sage = Color(red: 0.482, green: 0.894, blue: 0.584)
    static let amber = Color(red: 1.0, green: 0.784, blue: 0.341)
    static let rose = Color(red: 1.0, green: 0.302, blue: 0.427)

    static let ink = Color.white.opacity(0.92)
    static let inkSecondary = Color.white.opacity(0.62)
    static let inkTertiary = Color.white.opacity(0.4)
    static let hairline = Color.white.opacity(0.12)

    static func color(for modality: Modality) -> Color {
        switch modality {
        case .strength: ember
        case .running: sky
        case .yoga: heat
        }
    }

    static func color(for zone: LoadZone) -> Color {
        switch zone {
        case .building: rest
        case .undertrained: sky
        case .optimal: sage
        case .elevated: amber
        case .danger: rose
        }
    }
}

extension Modality {
    var symbolName: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .running: "figure.run"
        case .yoga: "figure.mind.and.body"
        }
    }

    var tint: Color { Palette.color(for: self) }
}

extension LoadZone {
    var tint: Color { Palette.color(for: self) }

    var symbolName: String {
        switch self {
        case .building: "chart.line.uptrend.xyaxis"
        case .undertrained: "arrow.down.right"
        case .optimal: "checkmark.seal.fill"
        case .elevated: "exclamationmark.triangle.fill"
        case .danger: "flame.fill"
        }
    }
}
