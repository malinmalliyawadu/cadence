import SwiftUI

/// SF Pro only. Words are set at medium weight so the screen stays calm; numbers carry the
/// weight, semibold or bold with monospaced digits so logging never jitters.
extension Font {
    static let title1 = Font.system(size: 30, weight: .medium)
    static let title2 = Font.system(size: 20, weight: .medium)
    static let rowTitle = Font.system(size: 17, weight: .medium)
    static let body2 = Font.system(size: 15, weight: .regular)
    static let label = Font.system(size: 13, weight: .medium)
    static let numeral = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let numeralLarge = Font.system(size: 48, weight: .bold).monospacedDigit()
    static let numeralSmall = Font.system(size: 16, weight: .semibold).monospacedDigit()
}

/// A screen's title: the session, the movement, the day. Medium weight, slightly tight.
struct DisplayText: View {
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .tracking(-size * 0.015)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Palette.ink)
    }
}
