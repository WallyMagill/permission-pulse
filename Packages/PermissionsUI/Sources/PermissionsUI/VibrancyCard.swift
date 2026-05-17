import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// Tahoe Vibrant card. Solid system-canvas fill (near-white in light mode,
// near-black-elevated in dark mode) instead of a translucent material, so
// the card reads as a confident clean surface — not as a blurry vibrancy
// panel. A 1px hairline stroke and a soft drop shadow give it lift.
struct VibrancyCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Self.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private static var cardFill: Color {
        #if canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color.white
        #endif
    }
}

extension View {
    func vibrancyCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(VibrancyCardStyle(cornerRadius: cornerRadius))
    }
}
