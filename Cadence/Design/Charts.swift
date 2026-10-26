import SwiftUI

/// The dial: a flat dark disc, a ring of fine ticks, and an accent
/// arc with a knob at its end. Whatever sits in the middle is the screen's one big number.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var tint: Color = Palette.accent
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: Center

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let clamped = max(0, min(1, progress))
            ZStack {
                Circle()
                    .fill(Palette.surface)
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                ticks(side: side)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                    .animation(.snappy(duration: 0.35), value: clamped)
                knob(side: side, progress: clamped)
                center
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func ticks(side: CGFloat) -> some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side / 2 - lineWidth * 2.2
            let inner = outer - side * 0.05
            let count = 120
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi
                var path = Path()
                path.move(to: CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: c.x + cos(angle) * outer, y: c.y + sin(angle) * outer))
                context.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1.4)
            }
        }
        .accessibilityHidden(true)
    }

    private func knob(side: CGFloat, progress: Double) -> some View {
        let radius = side / 2 - lineWidth / 2
        let angle = progress * 2 * .pi - .pi / 2
        return Circle()
            .fill(.white)
            .frame(width: lineWidth * 2.2, height: lineWidth * 2.2)
            .overlay { Circle().strokeBorder(tint, lineWidth: 3) }
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            .opacity(progress > 0 ? 1 : 0)
            .animation(.snappy(duration: 0.35), value: progress)
            .accessibilityHidden(true)
    }
}

/// Diagonal hatching, the texture of the bars.
struct Hatch: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// One day's bar, filling whatever frame it is given: deep blue with hatching and an accent
/// edge. A highlighted bar brightens. A planned bar (nothing logged yet) is the dashed
/// outline of what is coming.
struct HatchedBar: View {
    var isHighlighted = false
    var isPlanned = false

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: min(12, proxy.size.width / 2.4), style: .continuous)
            ZStack {
                if isPlanned {
                    shape.strokeBorder(isHighlighted ? Color.white.opacity(0.8) : Palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                } else {
                    shape.fill(isHighlighted ? Palette.accent.opacity(0.55) : Palette.accentDeep)
                    Hatch()
                        .stroke(isHighlighted ? Color.white.opacity(0.55) : Palette.accent.opacity(0.45), lineWidth: 1.1)
                        .clipShape(shape)
                    shape.strokeBorder(isHighlighted ? Color.white.opacity(0.85) : Palette.accent.opacity(0.75), lineWidth: isHighlighted ? 2 : 1.2)
                }
            }
        }
    }
}

/// A white capsule with the value, pinned above the highlighted bar.
struct ValueCallout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white, in: .capsule)
            .fixedSize()
    }
}
