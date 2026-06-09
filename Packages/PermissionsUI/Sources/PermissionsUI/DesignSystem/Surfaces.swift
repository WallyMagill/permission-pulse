import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension View {
    /// The app's single card surface: a solid system-canvas fill with a hairline
    /// and a soft drop shadow, so it reads as a confident, clean card rather than
    /// a blurry vibrancy panel. Solid by design — which also makes it inherently
    /// legible under Reduce Transparency (nothing translucent to reduce). The
    /// genuinely-translucent `.regularMaterial` surfaces migrate onto this card.
    /// (Thread B — preserves the original Tahoe Vibrant card treatment.)
    public func vibrancyCard(cornerRadius: CGFloat = PPRadius.medium) -> some View {
        modifier(VibrancyCard(cornerRadius: cornerRadius))
    }
}

private struct VibrancyCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill(Self.cardFill))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .clipShape(shape)
    }

    private static var cardFill: Color {
        #if canImport(AppKit)
        Color(nsColor: .textBackgroundColor)
        #else
        Color.white
        #endif
    }
}
