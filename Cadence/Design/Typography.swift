import SwiftUI

/// SF Pro only. Display text is heavy and tight so the session name reads as a poster,
/// numbers use the rounded design with monospaced digits so logging never jitters.
extension Font {
    static let display = Font.system(size: 56, weight: .heavy, design: .default)
    static let displaySmall = Font.system(size: 34, weight: .heavy, design: .default)
    static let headline2 = Font.system(size: 22, weight: .bold, design: .default)
    static let numeral = Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
    static let numeralLarge = Font.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit()
    static let numeralSmall = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
    static let label = Font.system(size: 13, weight: .semibold, design: .default)
}

struct DisplayText: View {
    let text: String
    var size: CGFloat = 56

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .tracking(-size * 0.035)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Palette.ink)
    }
}
