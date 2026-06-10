import SwiftUI
import PermissionsCore

// Uses contrast-safe PPBadgeStyle tokens so text passes WCAG AA (>= 4.5:1) on
// any surface — identical pattern to the Mock/Live data-source badges.
struct DispositionBadge: View {
    let disposition: BTMItem.Disposition

    var body: some View {
        Text(label)
            .ppFont(.badge)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, PPSpacing.xxs)
            .background(style.background, in: .capsule)
    }

    private var label: String {
        switch disposition {
        case .enabled:  String(localized: "Enabled")
        case .disabled: String(localized: "Disabled")
        case .unknown:  String(localized: "Unknown")
        }
    }

    private var style: PPBadgeStyle {
        switch disposition {
        case .enabled:  .enabled
        case .disabled: .disabled
        case .unknown:  .dispositionUnknown
        }
    }
}
