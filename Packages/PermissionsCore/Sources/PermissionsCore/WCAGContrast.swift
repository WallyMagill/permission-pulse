import Foundation

/// WCAG 2.x relative-luminance contrast ratio for sRGB color components in 0...1.
/// Pure math (no UI) so badge color pairs can be unit-tested. (Thread B)
public enum WCAGContrast {
    public static func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Contrast ratio (1...21). Order-independent.
    public static func ratio(
        foreground fg: (Double, Double, Double),
        background bg: (Double, Double, Double)
    ) -> Double {
        let l1 = relativeLuminance(fg.0, fg.1, fg.2)
        let l2 = relativeLuminance(bg.0, bg.1, bg.2)
        let hi = Swift.max(l1, l2)
        let lo = Swift.min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }
}
