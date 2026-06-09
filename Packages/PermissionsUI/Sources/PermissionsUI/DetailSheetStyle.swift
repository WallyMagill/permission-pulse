import SwiftUI
import PermissionsCore

// Shared visual language for every detail sheet — section labels, key/value
// rows, risk panels, the gradient symbol tile used when an item has no real
// app icon, the accent-blue service pill, and the close-only footer. All
// built on top of `.vibrancyCard()` so sheets feel like part of the same
// window, not a stranger pop-up.

struct SheetSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SheetKVRow {
    let key: String
    let value: String
    let monospaced: Bool

    init(_ key: String, _ value: String, mono: Bool = false) {
        self.key = key
        self.value = value
        self.monospaced = mono
    }
}

struct SheetKVCard: View {
    let rows: [SheetKVRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                kvRow(row)
            }
        }
        .vibrancyCard()
    }

    private func kvRow(_ row: SheetKVRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.key)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(row.value)
                .font(row.monospaced ? .system(size: 12.5).monospaced() : .system(size: 12.5))
                .fontWeight(row.monospaced ? .regular : .medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

struct SheetRiskPanel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .vibrancyCard()
    }
}

struct SheetGradientTile: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.37, green: 0.55, blue: 1.0),
                        Color(red: 0.04, green: 0.52, blue: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            )
            .shadow(color: Color.blue.opacity(0.35), radius: 5, y: 1)
    }
}

func sheetFormattedDate(_ date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
}

// Short, month-day formatter for service pills. "MMM d" template → "Mar 14"
// in en-US; locale-aware (e.g. "14 mars" in fr-FR).
func sheetShortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMM d")
    return formatter.string(from: date)
}

// Accent-blue capsule button. Each pill represents a granted service with
// its grant date; tap opens that service's pane in System Settings.
struct ServicePillButton: View {
    let service: PermissionService
    let date: Date?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(service.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                if let date {
                    Text("·")
                        .font(.system(size: 11.5))
                        .opacity(0.5)
                    Text(sheetShortDate(date))
                        .font(.system(size: 11.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(Color.accentColor)
            .background(
                Capsule().fill(
                    Color.accentColor.opacity(isHovering ? 0.22 : 0.14)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityHint(String(localized: "Opens \(service.displayName) in System Settings"))
    }
}

// Close-only footer, right-aligned. Used for sheets with no primary action
// (per the locked footer convention).
struct SheetCloseFooter: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button(String(localized: "Close")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

// Wrapping flow layout — like CSS flex-wrap. Used by the service-pill grid
// in the per-app detail sheet so pills wrap onto new lines when the sheet's
// width can't fit them all.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let arranged = arrange(sizes: sizes, maxWidth: maxWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : arranged.usedWidth, height: arranged.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let arranged = arrange(sizes: sizes, maxWidth: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let pos = arranged.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }

    private func arrange(
        sizes: [CGSize],
        maxWidth: CGFloat
    ) -> (positions: [CGPoint], totalHeight: CGFloat, usedWidth: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widestLine: CGFloat = 0
        for size in sizes {
            if x + size.width > maxWidth, x > 0 {
                widestLine = max(widestLine, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widestLine = max(widestLine, x - spacing)
        return (positions, y + lineHeight, widestLine)
    }
}
