import SwiftUI

/// Sora, a variable font bundled with the app, the watch app and the widget extension (`UIAppFonts`).
/// Words are set at medium weight so the screen stays calm; numbers carry the weight, semibold or
/// bold with monospaced digits so logging never jitters. SF Symbols keep `Font.system` sizes.
extension Font {
    static let family = "Sora"

    /// Sora at a fixed size, the counterpart of `Font.system(size:weight:)`.
    static func cadence(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(family, fixedSize: size).weight(weight)
    }

    static let title1 = Font.cadence(size: 30, weight: .medium)
    static let title2 = Font.cadence(size: 20, weight: .medium)
    static let rowTitle = Font.cadence(size: 17, weight: .medium)
    static let body2 = Font.cadence(size: 15)
    static let label = Font.cadence(size: 13, weight: .medium)
    static let footnote2 = Font.cadence(size: 13)
    static let numeral = Font.cadence(size: 26, weight: .semibold).monospacedDigit()
    static let numeralLarge = Font.cadence(size: 48, weight: .bold).monospacedDigit()
    static let numeralSmall = Font.cadence(size: 16, weight: .semibold).monospacedDigit()
    /// Chart axis labels.
    static let axis = Font.cadence(size: 11, weight: .medium).monospacedDigit()
}

#if canImport(UIKit)
import UIKit

extension UIFont {
    /// Sora for UIKit chrome SwiftUI does not reach: navigation bar titles and tab bar labels.
    /// The weight sets the variable font's `wght` axis directly, so every weight resolves.
    static func cadence(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let wght: Double = switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy, .black: 800
        default: 400
        }
        let wghtAxis = 0x7767_6874 // "wght"
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: Font.family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtAxis: wght],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}
#endif

/// A screen's title: the session, the movement, the day. Medium weight, slightly tight.
struct DisplayText: View {
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.cadence(size: size, weight: .medium))
            .tracking(-size * 0.015)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Palette.ink)
    }
}
