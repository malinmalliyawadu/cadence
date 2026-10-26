import SwiftUI

/// Liquid Glass helpers. Glass is reserved for surfaces you act on; passive text sits
/// directly on the backdrop so the material keeps its meaning.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct GlassPill: View {
    var symbol: String
    var text: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint ?? Palette.ink)
            Text(text)
                .font(.label)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A row that reads as a control. Interactive glass lifts on touch.
struct GlassRow<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.18)).interactive() } ?? Glass.regular.interactive(), in: .rect(cornerRadius: 22))
    }
}

struct ModalityBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}
