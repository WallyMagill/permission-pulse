import SwiftUI
import PermissionsCore

struct LaunchAgentRow: View {
    let item: LaunchAgentItem
    var programMissing: Bool = false

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            Image(systemName: "gearshape.2")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(item.label).ppFont(.body).lineLimit(1)
                subtitle
                if programMissing {
                    MissingProgramNote()
                }
            }
            Spacer(minLength: PPSpacing.sm)
            if item.isDisabled {
                DispositionBadge(disposition: .disabled)
            }
        }
        .padding(.vertical, PPSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: some View {
        HStack(spacing: PPSpacing.xxs) {
            if !item.detailsReadable {
                Image(systemName: "lock.fill")
                    .accessibilityHidden(true)
            }
            Text(LaunchAgentDisplay.secondaryLine(item))
        }
        .ppFont(.metadata)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct MissingProgramNote: View {
    var body: some View {
        HStack(spacing: PPSpacing.xxs) {
            Image(systemName: "questionmark.folder")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(LaunchAgentDisplay.programNotFound)
                .foregroundStyle(.secondary)
        }
        .ppFont(.metadata)
        .lineLimit(2)
    }
}
