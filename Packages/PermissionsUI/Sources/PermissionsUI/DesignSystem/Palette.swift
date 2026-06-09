import SwiftUI

/// Semantic colors. Category + status are fixed (accent-independent); interactive
/// elements keep `Color.accentColor` (NOT defined here). (Thread B)
public enum PPColor {
    // Category / wayfinding
    public static let permissions = Color.blue
    public static let launchAgents = Color.purple
    public static let backgroundItems = Color.teal
    public static let recentChanges = Color.orange
    public static let staleApps = Color.pink

    // Status / semantic. (warning shares orange with the recentChanges category
    // by design — the app uses orange for both "attention" and "recent"; the two
    // are never co-located, so the shared hue is intentional, not an alias bug.)
    public static let success = Color.green
    public static let warning = Color.orange
    public static let danger = Color.red

    // Brand mark (fixed; a logo, not accent-driven)
    public static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.37, green: 0.55, blue: 1.0),
            Color(red: 0.04, green: 0.52, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Contrast-safe badge styles: dark, saturated text on a pale tint fill. The fg/bg
/// are FIXED sRGB pairs (self-contained — they do not inherit the surface), so
/// contrast is identical in light and dark and is unit-verified >= 4.5:1. (Thread B)
public enum PPBadgeStyle {
    case mock
    case live
    /// BTMItem.Disposition.enabled — green family
    case enabled
    /// BTMItem.Disposition.disabled — slate-gray family
    case disabled
    /// BTMItem.Disposition.unknown — amber/gray family
    case dispositionUnknown

    public var foregroundRGB: (Double, Double, Double) {
        switch self {
        case .mock:                (0.45, 0.22, 0.0)
        case .live:                (0.0, 0.33, 0.13)
        case .enabled:             (0.0, 0.33, 0.13)
        case .disabled:            (0.28, 0.30, 0.33)
        case .dispositionUnknown:  (0.45, 0.22, 0.0)
        }
    }

    public var backgroundRGB: (Double, Double, Double) {
        switch self {
        case .mock:                (0.99, 0.92, 0.82)
        case .live:                (0.86, 0.96, 0.89)
        case .enabled:             (0.86, 0.96, 0.89)
        case .disabled:            (0.90, 0.91, 0.93)
        case .dispositionUnknown:  (0.99, 0.92, 0.82)
        }
    }

    public var foreground: Color {
        Color(.sRGB, red: foregroundRGB.0, green: foregroundRGB.1, blue: foregroundRGB.2)
    }
    public var background: Color {
        Color(.sRGB, red: backgroundRGB.0, green: backgroundRGB.1, blue: backgroundRGB.2)
    }
}
