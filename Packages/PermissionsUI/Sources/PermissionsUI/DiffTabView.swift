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
    var snapshotStoreUnavailable: Bool = false
    var diffUnavailable: Bool = false
    @Environment(DismissedDiffEntryStore.self) private var dismissedStore
    @State private var pendingDismiss: PendingDismiss?

    private let snoozeDuration: TimeInterval = 7 * 24 * 60 * 60

    private struct PendingDismiss: Identifiable {
        var id: String { key }
        let key: String
        let summary: String
    }

    var body: some View {
        let now = Date()

        if snapshotStoreUnavailable {
            unavailableState(
                headline: String(localized: "Snapshot history unavailable"),
                detail: String(localized: "Permission Pulse couldn't open its local database, so it can't track changes. Try Reset All Data in Preferences.")
            )
        } else if diffUnavailable {
            unavailableState(
                headline: String(localized: "Couldn't read changes"),
                detail: String(localized: "A problem reading the local database prevented computing changes. Try Refresh.")
            )
        } else if let diff {
            let tccVisible = filtered(tccRows(diff.tcc), now: now)
            let btmVisible = filtered(btmRows(diff.btm), now: now)
            let laVisible = filtered(launchAgentRows(diff.launchAgents), now: now)
            let totalVisible = tccVisible.count + btmVisible.count + laVisible.count

            if totalVisible > 0 {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    if !tccVisible.isEmpty {
                        section(title: String(localized: "Permissions"), rows: tccVisible)
                    }
                    if !btmVisible.isEmpty {
                        section(title: String(localized: "Background Items"), rows: btmVisible)
                    }
                    if !laVisible.isEmpty {
                        section(title: String(localized: "Launch Agents"), rows: laVisible)
                    }
                    Text(String(localized: "Use the ⋯ menu on a row to snooze or dismiss a change."))
                        .ppFont(.metadata)
                        .foregroundStyle(.tertiary)
                }
                .alert(
                    String(localized: "Dismiss this change forever?"),
                    isPresented: Binding(
                        get: { pendingDismiss != nil },
                        set: { if !$0 { pendingDismiss = nil } }
                    ),
                    presenting: pendingDismiss
                ) { candidate in
                    Button(String(localized: "Dismiss forever"), role: .destructive) {
                        dismissedStore.dismissForever(key: candidate.key)
                        pendingDismiss = nil
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {
                        pendingDismiss = nil
                    }
                } message: { candidate in
                    Text(String(localized: "Permission Pulse will stop showing this change: \(candidate.summary). Use Reset All Data in Preferences to bring it back."))
                }
            } else {
                emptyContentState
            }
        } else {
            emptyNoPriorState
        }
    }

    private func section(title: String, rows: [ChangeRow.Kind]) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text(title).ppFont(.cardHeader)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, kind in
                    let key = DiffEntryKey.key(for: kind)
                    ChangeRow(
                        kind: kind,
                        onDismissForever: {
                            pendingDismiss = PendingDismiss(
                                key: key,
                                summary: ChangeRow.summary(for: kind)
                            )
                        },
                        onSnooze: {
                            dismissedStore.snooze(
                                key: key,
                                until: Date().addingTimeInterval(snoozeDuration)
                            )
                        }
                    )
                    .padding(.vertical, PPSpacing.sm)
                    .padding(.horizontal, PPSpacing.md)
                }
            }
            .vibrancyCard()
        }
    }

    private func filtered(_ rows: [ChangeRow.Kind], now: Date) -> [ChangeRow.Kind] {
        rows.filter { !dismissedStore.isDismissed(key: DiffEntryKey.key(for: $0), asOf: now) }
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
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(emptyNoPriorHeadline).ppFont(.cardHeader)
            Text(String(localized: "Permission Pulse needs at least one prior snapshot. Come back tomorrow."))
                .ppFont(.body)
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
                .accessibilityHidden(true)
            Text(emptyContentHeadline).ppFont(.cardHeader)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    private func unavailableState(headline: String, detail: String) -> some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(headline).ppFont(.cardHeader)
            Text(detail)
                .ppFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
