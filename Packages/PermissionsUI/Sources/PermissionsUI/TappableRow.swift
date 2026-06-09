import AppKit
import SwiftUI

// A consistent affordance for a row that opens a detail sheet on tap:
//   • content + optional trailing slot
//   • trailing chevron.right glyph indicating "there is more behind this row"
//   • pointing-hand cursor on hover (NSCursor push/pop)
//   • subtle background highlight on hover and press
//
// Parent containers should apply `.clipShape(RoundedRectangle(...))` so the
// hover background doesn't bleed past their rounded corners.
struct TappableRow<Content: View, Trailing: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, PPSpacing.sm)
            .padding(.horizontal, PPSpacing.md)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Opens details"))
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension TappableRow where Trailing == EmptyView {
    init(
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.content = content
        self.trailing = { EmptyView() }
    }
}
