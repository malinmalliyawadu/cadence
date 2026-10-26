import SwiftUI

/// The black every screen sits on.
struct ScreenBackground: View {
    var body: some View {
        Palette.canvas.ignoresSafeArea()
    }
}

extension View {
    /// Keeps scrolled content out from under the status bar on screens without a navigation bar.
    func statusBarScrim() -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                Palette.canvas
                    .frame(height: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
        }
    }
}

/// A flat card with a hairline edge. `isActive` swaps the hairline
/// for the accent, the way the set being logged is outlined.
struct Card<Content: View>: View {
    var isActive = false
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(cornerRadius: cornerRadius, isActive: isActive)
    }
}

extension View {
    func surface(cornerRadius: CGFloat = 22, isActive: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(isActive ? Palette.accent : Palette.hairline, lineWidth: isActive ? 1.5 : 1)
                }
        }
    }
}

/// Icon and value in a capsule: "55 min", "19 sets". Outlined by default; `filled` for
/// chips that sit on a card and would otherwise outline against an outline.
struct Chip: View {
    var symbol: String?
    var text: String
    var tint: Color = Palette.ink
    var filled = false

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background {
            Capsule()
                .fill(filled ? Palette.raised : Color.clear)
                .overlay { Capsule().strokeBorder(filled ? Color.clear : Palette.stroke, lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small outlined circle holding a glyph, used ahead of a stat's title.
struct IconDisc: View {
    let symbol: String
    var tint: Color = Palette.ink
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .overlay { Circle().strokeBorder(Palette.stroke, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// The session thumbnail: a rounded tile with the modality glyph on a flat tint of its hue.
struct SessionTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                    }
            }
            .accessibilityHidden(true)
    }
}

/// A section's title with an optional trailing control: "See all", or a menu chip.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.title2)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// The label of a dropdown: "This week" with a chevron, in a filled capsule.
struct MenuChipLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(Palette.raised, in: .capsule)
        .contentShape(.capsule)
    }
}

/// A dropdown chip that picks one of a few values.
struct MenuChip<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { value, label in Text(label).tag(value) }
            }
        } label: {
            MenuChipLabel(text: options.first { $0.0 == selection }?.1 ?? title)
        }
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
    }
}

/// A row of capsules that behaves like a segmented control. The selected one fills with the accent.
struct ChipPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                let isSelected = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(label)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.white : Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            Capsule()
                                .fill(isSelected ? Palette.accent : Palette.raised)
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The one blue capsule on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Palette.accent.opacity(isEnabled ? 1 : 0.35), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Everything that is an action but not the action.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Palette.ink.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Palette.raised, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A thin track with an accent fill, for sets logged against sets planned.
struct ProgressBar: View {
    let value: Double
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue(Format.percent(value))
    }
}
