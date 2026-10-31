import SwiftUI

/// The dial: a flat dark disc, a ring of fine ticks, and an accent arc with the icon's mint dot
/// at its head, in a gap the arc leaves for it. Full, the ring is the icon: an open ring with the
/// dot in its gap. Whatever sits in the middle is the screen's one big number.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var tint: Color = Palette.accent
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: Center

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let clamped = max(0, min(1, progress))
            let gap = dotGap(side: side)
            ZStack {
                Circle()
                    .fill(Palette.surface)
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                ticks(side: side)
                Circle()
                    .trim(from: max(0, clamped - (1 - gap)), to: max(0, clamped - gap))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                    .opacity(clamped > gap ? 1 : 0)
                    .animation(Motion.settle, value: clamped)
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

    /// The share of the ring between the dot's centre and the arc's end: the arc's round cap,
    /// some clear space, and half the dot, as on the icon.
    private func dotGap(side: CGFloat) -> Double {
        let radius = side / 2 - lineWidth / 2
        return (lineWidth * 1.3) / (2 * .pi * radius)
    }

    private func knob(side: CGFloat, progress: Double) -> some View {
        let radius = side / 2 - lineWidth / 2
        let angle = progress * 2 * .pi - .pi / 2
        return Circle()
            .fill(Palette.today)
            .frame(width: lineWidth * 0.9, height: lineWidth * 0.9)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            .opacity(progress > 0 ? 1 : 0)
            .animation(Motion.settle, value: progress)
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

/// One day's bar, filling whatever frame it is given: deep violet with hatching and an accent
/// edge. Today's bar is the icon's mint. A planned bar (nothing logged yet) is the dashed
/// outline of what is coming.
struct HatchedBar: View {
    var isToday = false
    var isPlanned = false

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: min(12, proxy.size.width / 2.4), style: .continuous)
            let edge = isToday ? Palette.today : Palette.accent
            ZStack {
                if isPlanned {
                    shape.strokeBorder(edge.opacity(isToday ? 0.9 : 0.6), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                } else {
                    shape.fill(isToday ? Palette.today.opacity(0.22) : Palette.accentDeep)
                    Hatch()
                        .stroke(edge.opacity(isToday ? 0.6 : 0.45), lineWidth: 1.1)
                        .clipShape(shape)
                    shape.strokeBorder(edge.opacity(isToday ? 1 : 0.75), lineWidth: isToday ? 2 : 1.2)
                }
            }
        }
    }
}

/// A mint capsule with the value, pinned above today's bar.
struct ValueCallout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.cadence(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.today, in: .capsule)
            .fixedSize()
    }
}

/// The app icon's mark: an open ring, the training cycle, with a dot in its gap for today.
/// The geometry is scripts/generate_app_icon.py's, scaled so the ring fills the frame. With
/// `drawsIn`, the ring sweeps closed and the dot lands, unless Reduce Motion is on.
struct OrbitMark: View {
    var drawsIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    // On the icon's 1024 point canvas: ring radius 262, stroke 136, an 84 degree gap centred
    // 45 degrees clockwise from twelve, and a dot 0.36 of the stroke wide on the ring's centre line.
    private static let span: CGFloat = 262 * 2 + 136
    private static let gap = 84.0
    private static let gapCentre = 45.0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / Self.span
            let radius = 262 * unit
            let angle = Angle.degrees(Self.gapCentre).radians
            let shown = drawn || !drawsIn || reduceMotion
            ZStack {
                Circle()
                    .trim(from: 0, to: shown ? (360 - Self.gap) / 360 : 0)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 136 * unit, lineCap: .round))
                    .rotationEffect(.degrees(Self.gapCentre + Self.gap / 2 - 90))
                    .frame(width: radius * 2, height: radius * 2)
                Circle()
                    .fill(Palette.today)
                    .frame(width: 136 * 0.72 * unit, height: 136 * 0.72 * unit)
                    .scaleEffect(shown ? 1 : 0.2)
                    .opacity(shown ? 1 : 0)
                    .offset(x: sin(angle) * radius, y: -cos(angle) * radius)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear {
            guard drawsIn, !reduceMotion, !drawn else { return }
            withAnimation(.easeOut(duration: 0.7)) { drawn = true }
        }
    }
}
