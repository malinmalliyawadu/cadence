import SwiftUI
import TrainingEngine

/// Semantic colour tokens. True black, two flat greys for surfaces, and one
/// electric blue that marks whatever is active: the session to start, the set being logged,
/// today's bar. Running and yoga get cool neighbours of the blue so charts can tell them apart.
enum Palette {
    static let canvas = Color.black
    static let surface = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let raised = Color(red: 0.137, green: 0.137, blue: 0.153)

    static let accent = Color(red: 0.200, green: 0.408, blue: 1.0)
    static let accentDeep = Color(red: 0.090, green: 0.165, blue: 0.420)

    static let strength = accent
    static let sky = Color(red: 0.271, green: 0.808, blue: 0.890)
    static let violet = Color(red: 0.663, green: 0.533, blue: 1.0)
    static let rest = Color(red: 0.52, green: 0.54, blue: 0.60)

    static let sage = Color(red: 0.373, green: 0.851, blue: 0.565)
    static let amber = Color(red: 1.0, green: 0.769, blue: 0.341)
    static let rose = Color(red: 1.0, green: 0.361, blue: 0.459)

    static let ink = Color.white.opacity(0.95)
    static let inkSecondary = Color.white.opacity(0.62)
    static let inkTertiary = Color.white.opacity(0.4)
    static let hairline = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.14)

    static func color(for modality: Modality) -> Color {
        switch modality {
        case .strength: strength
        case .running: sky
        case .yoga: violet
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
