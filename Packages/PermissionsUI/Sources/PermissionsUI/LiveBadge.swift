import SwiftUI

public struct LiveBadge: View {
    public init() {}

    public var body: some View {
        Text(String(localized: "Live"))
            .ppFont(.badge)
            .foregroundStyle(PPBadgeStyle.live.foreground)
            .padding(.horizontal, PPSpacing.xs)
            .padding(.vertical, PPSpacing.xxs)
            .background(PPBadgeStyle.live.background, in: .capsule)
            .accessibilityLabel(String(localized: "Live data"))
    }
}
