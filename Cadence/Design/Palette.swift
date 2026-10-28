import SwiftUI
import TrainingEngine

/// Semantic colour tokens, taken from the app icon: a violet ring with a mint dot for today on
/// deep indigo. True black canvas, surfaces with a trace of the icon's indigo, and the violet
/// marks whatever is active: the session to start, the set being logged, the primary button.
/// Mint is the dot, kept for today alone. Running and yoga get sky and orchid, either side of
/// the violet, so charts can tell the modalities apart.
enum Palette {
    static let canvas = Color.black
    static let surface = Color(red: 0.082, green: 0.063, blue: 0.125)
    static let raised = Color(red: 0.137, green: 0.106, blue: 0.200)

    /// The icon's ring, #B47CFF.
    static let accent = Color(red: 0.706, green: 0.486, blue: 1.0)
    static let accentDeep = Color(red: 0.169, green: 0.102, blue: 0.341)
    /// The icon's ground, #12082E: text and glyphs on an accent fill.
    static let onAccent = Color(red: 0.071, green: 0.031, blue: 0.180)
    /// The icon's dot, #5CF2D6: today.
    static let today = Color(red: 0.361, green: 0.949, blue: 0.839)

    static let strength = accent
    static let sky = Color(red: 0.345, green: 0.706, blue: 1.0)
    static let orchid = Color(red: 0.949, green: 0.545, blue: 0.851)
    static let rest = Color(red: 0.54, green: 0.52, blue: 0.62)

    static let sage = Color(red: 0.373, green: 0.851, blue: 0.565)
    static let amber = Color(red: 1.0, green: 0.769, blue: 0.341)
    static let rose = Color(red: 1.0, green: 0.361, blue: 0.459)

    static let ink = Color.white.opacity(0.95)
    static let inkSecondary = Color.white.opacity(0.62)
    static let inkTertiary = Color.white.opacity(0.4)
    private static let lavender = Color(red: 0.84, green: 0.80, blue: 1.0)
    static let hairline = lavender.opacity(0.09)
    static let stroke = lavender.opacity(0.16)

    static func color(for modality: Modality) -> Color {
        switch modality {
        case .strength: strength
        case .running: sky
        case .yoga: orchid
        }
    }

    static func color(for level: RecoveryLevel) -> Color {
        switch level {
        case .recovered: sage
        case .fair: sky
        case .low: amber
        case .poor: rose
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
