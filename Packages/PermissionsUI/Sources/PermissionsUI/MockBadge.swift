import SwiftUI

public struct MockBadge: View {
    public init() {}

    public var body: some View {
        Text("Mock")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange, in: .capsule)
    }
}
