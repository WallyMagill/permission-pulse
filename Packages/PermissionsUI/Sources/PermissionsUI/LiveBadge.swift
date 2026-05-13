import SwiftUI

public struct LiveBadge: View {
    public init() {}

    public var body: some View {
        Text("Live")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green, in: .capsule)
    }
}
