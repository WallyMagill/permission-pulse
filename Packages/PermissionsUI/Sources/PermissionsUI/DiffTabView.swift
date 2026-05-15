import SwiftUI
import PermissionsCore
import PermissionsStore

enum DiffWindowLabel: Sendable {
    case yesterday
    case lastWeek
}

struct DiffTabView: View {
    let diff: SnapshotDiffs?
    let windowLabel: DiffWindowLabel

    var body: some View {
        if let diff {
            if diff.hasContent {
                VStack(alignment: .leading, spacing: 16) {
                    if diff.tcc.hasContent {
                        section(
                            title: String(localized: "Permissions"),
                            rows: tccRows(diff.tcc)
                        )
                    }
                    if diff.btm.hasContent {
                        section(
                            title: String(localized: "Background Items"),
                            rows: btmRows(diff.btm)
                        )
                    }
                    if diff.launchAgents.hasContent {
                        section(
                            title: String(localized: "Launch Agents"),
                            rows: launchAgentRows(diff.launchAgents)
                        )
                    }
                }
            } else {
                emptyContentState
            }
        } else {
            emptyNoPriorState
        }
    }

    private func section(title: String, rows: [ChangeRow.Kind]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, kind in
                    ChangeRow(kind: kind)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func tccRows(_ diff: TCCGrantsDiff) -> [ChangeRow.Kind] {
        diff.added.map { ChangeRow.Kind.granted($0) }
            + diff.removed.map { ChangeRow.Kind.revoked($0) }
    }

    private func btmRows(_ diff: BTMItemsDiff) -> [ChangeRow.Kind] {
        diff.added.map { ChangeRow.Kind.btmAdded($0) }
            + diff.removed.map { ChangeRow.Kind.btmRemoved($0) }
            + diff.changed.map { ChangeRow.Kind.btmDispositionFlipped($0) }
    }

    private func launchAgentRows(_ diff: LaunchAgentsDiff) -> [ChangeRow.Kind] {
        diff.added.map { ChangeRow.Kind.launchAgentAdded($0) }
            + diff.removed.map { ChangeRow.Kind.launchAgentRemoved($0) }
            + diff.changed.map { ChangeRow.Kind.launchAgentFlipped($0) }
    }

    private var emptyNoPriorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(emptyNoPriorHeadline).font(.headline)
            Text(String(localized: "Permission Pulse needs at least one prior snapshot. Come back tomorrow."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    private var emptyContentState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(emptyContentHeadline).font(.headline)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    private var emptyNoPriorHeadline: String {
        switch windowLabel {
        case .yesterday: return String(localized: "No snapshot from yesterday yet")
        case .lastWeek:  return String(localized: "No snapshot from last week yet")
        }
    }

    private var emptyContentHeadline: String {
        switch windowLabel {
        case .yesterday: return String(localized: "No changes since yesterday")
        case .lastWeek:  return String(localized: "No changes in the last week")
        }
    }
}
