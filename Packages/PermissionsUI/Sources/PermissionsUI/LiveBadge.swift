import SwiftUI

public struct LiveBadge: View {
    public init() {}

    public var body: some View {
        Text(String(localized: "Live"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green, in: .capsule)
            .accessibilityLabel(String(localized: "Live data"))
    }
}
