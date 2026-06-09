import SwiftUI

public struct MockBadge: View {
    public init() {}

    public var body: some View {
        Text(String(localized: "Mock"))
            .ppFont(.badge)
            .foregroundStyle(PPBadgeStyle.mock.foreground)
            .padding(.horizontal, PPSpacing.xs)
            .padding(.vertical, PPSpacing.xxs)
            .background(PPBadgeStyle.mock.background, in: .capsule)
            .accessibilityLabel(String(localized: "Mock data"))
    }
}
