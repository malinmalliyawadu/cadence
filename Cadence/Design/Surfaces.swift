import SwiftUI

/// Spacing every screen shares.
enum Metrics {
    /// The side margin, the same as the system's: content lines up with the large title, the
    /// back button and the toolbar's glass.
    static let gutter: CGFloat = 16
}

/// The black every screen sits on.
struct ScreenBackground: View {
    var body: some View {
        Palette.canvas.ignoresSafeArea()
    }
}

/// A flat card, no edge: the indigo surface against the black is the whole of it. What is active
/// says so with its content (the violet button, the set being logged), never with an outline.
struct Card<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(cornerRadius: cornerRadius)
    }
}

extension View {
    func surface(cornerRadius: CGFloat = 22) -> some View {
        background(Palette.surface, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Icon and value in a capsule: "55 min", "19 sets". Facts are outlined; `glass` is for a chip
/// that does something ("Change", "Add set"), so actions read apart from facts at a glance.
struct Chip: View {
    var symbol: String?
    var text: String
    var tint: Color = Palette.ink
    var glass = false

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.cadence(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background {
            if !glass { Capsule().strokeBorder(Palette.stroke, lineWidth: 1) }
        }
        .contentShape(.capsule)
        .glassEffect(glass ? .regular.interactive() : .identity, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// A round glass control holding a glyph: a stepper's minus and plus, skip, close.
struct GlassIcon: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// A status word in its tint, outlined in the same: "Sweet spot", "Recovered", "Too flat".
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.label)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay { Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1) }
            .fixedSize()
    }
}

/// Beside a title whose figure opens an explainer.
struct InfoGlyph: View {
    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkTertiary)
            .accessibilityHidden(true)
    }
}

/// The glyph ahead of a card's title: no disc or outline, flush with the card's text, in a fixed
/// slot so titles line up whichever glyph leads them. The slot is as tall as a title row needs
/// to be, so the card's content keeps its distance below the title.
struct TitleIcon: View {
    let symbol: String
    var tint: Color = Palette.ink

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 34, alignment: .leading)
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
            .contentTransition(.symbolEffect(.replace))
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

/// The label of a dropdown: "This week" with a chevron, on glass. In a toolbar the system draws
/// the glass, so the label leaves it out.
struct MenuChipLabel: View {
    let text: String
    var glass = true

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.cadence(size: 14, weight: .medium))
                .contentTransition(.interpolate)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, glass ? 14 : 4)
        .frame(minHeight: 34)
        .contentShape(.capsule)
        .glassEffect(glass ? .regular.interactive() : .identity, in: .capsule)
    }
}

/// A dropdown chip that picks one of a few values. Whatever the value drives moves to its new
/// state rather than jumping.
struct MenuChip<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var glass = true

    var body: some View {
        Menu {
            Picker(title, selection: $selection.animation(Motion.settle)) {
                ForEach(options, id: \.0) { value, label in Text(label).tag(value) }
            }
        } label: {
            MenuChipLabel(text: options.first { $0.0 == selection }?.1 ?? title, glass: glass)
        }
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
    }
}

/// A segmented control on glass: one glass track, with the violet sliding to the segment picked.
/// History's pages, reps in reserve, a session's half.
struct ChipPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                let isSelected = value == selection
                Button {
                    withAnimation(Motion.settle) { selection = value }
                } label: {
                    Text(label)
                        .font(.cadence(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? Palette.onAccent : Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if isSelected {
                                Capsule().fill(Palette.accent).matchedGeometryEffect(id: "selection", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.control)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The one violet capsule on a screen, its label in the icon's indigo: glass tinted with the
/// icon's violet, so it is the thing to do and still made of what everything around it is.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cadence(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? Palette.onAccent : Palette.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(.capsule)
            .glassEffect(isEnabled ? .regular.tint(Palette.accent).interactive() : .regular, in: .capsule)
            .animation(Motion.settle, value: isEnabled)
    }
}

/// Everything that is an action but not the action, on clear glass.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cadence(size: 16, weight: .medium))
            .foregroundStyle(Palette.ink.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(.capsule)
            .glassEffect(isEnabled ? .regular.interactive() : .regular, in: .capsule)
    }
}

/// A card, or part of one, that opens something: it dims under the finger, nothing more, so a
/// section inside a card never shrinks away from its neighbours.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A small control that is not glass (a set row's pencil, a warm-up, a segment): it gives a
/// little under the finger, so the tap is felt before it is acted on.
struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A choice laid out as a row or a tile (a focus, a run type, a day, a replacement movement):
/// glass in the shape it is given, lit with the violet when it is the current one.
struct OptionButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 18
    var isCurrent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(isCurrent ? .regular.tint(Palette.accent.opacity(0.35)).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == OptionButtonStyle {
    static var option: OptionButtonStyle { OptionButtonStyle() }
    static func option(cornerRadius: CGFloat = 18, isCurrent: Bool) -> OptionButtonStyle {
        OptionButtonStyle(cornerRadius: cornerRadius, isCurrent: isCurrent)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == ControlButtonStyle {
    static var control: ControlButtonStyle { ControlButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A thin track with an accent fill, for sets logged against sets planned. The fill moves to a
/// new value; `animation` sets how (the rest timer's runs linearly with the clock).
struct ProgressBar: View {
    let value: Double
    var tint: Color = Palette.accent
    var animation: Animation = Motion.settle

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * proxy.size.width)
                    .animation(animation, value: value)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue(Format.percent(value))
    }
}

/// Chips in rows that wrap: as many as fit on a line, the rest on the next. Nothing scrolls
/// sideways or truncates, so a wet, windy day just takes a second line.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
