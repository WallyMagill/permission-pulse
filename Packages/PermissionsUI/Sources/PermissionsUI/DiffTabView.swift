import SwiftUI
import PermissionsCore
import PermissionsStore

struct DiffTabView: View {
    let diff: SnapshotDiffs?
    let window: RecentChangesWindow
    var searchText: String = ""
    var storeProblem: SnapshotStoreProblem?
    var diffUnavailable: Bool = false
    var permissionScope: PermissionScope = .full
    var onMarkAllReviewed: (() -> Void)?
    @Environment(DismissedDiffEntryStore.self) private var dismissedStore
    @State private var pendingDismiss: PendingDismiss?

    private let snoozeDuration: TimeInterval = 7 * 24 * 60 * 60

    private struct PendingDismiss: Identifiable {
        var id: String { key }
        let key: String
        let summary: String
    }

    var body: some View {
        if let storeProblem {
            storeProblemView(storeProblem)
        } else if diffUnavailable {
            ContentUnavailableView(
                String(localized: "Couldn't Read Changes"),
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(String(localized: "A problem reading the local database prevented computing changes. Try Rescan."))
            )
        } else if let diff {
            let visible = ChangeRow.filtered(
                dismissedStore.visibleEntries(in: diff, asOf: Date()),
                searchText: searchText
            )
            if !visible.isEmpty {
                diffList(visible)
            } else if let hidden = permissionScope.hiddenService(matching: searchText) {
                HiddenServiceSearchView(service: hidden)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                emptyState(diff)
            }
        } else {
            ContentUnavailableView(
                String(localized: "Nothing to compare yet"),
                systemImage: "clock.arrow.circlepath",
                description: Text(noHistoryDescription)
            )
        }
    }

    private func storeProblemView(_ problem: SnapshotStoreProblem) -> some View {
        let title: String
        let message: String
        switch problem {
        case .createdByNewerVersion:
            title = String(localized: "History From a Newer Version")
            message = String(localized: "History was created by a newer version of Permission Pulse. Update the app to keep using it.")
        case .corrupt:
            title = String(localized: "History Is Damaged")
            message = String(localized: "Permission Pulse's history database is damaged and can't be read. Use Reset All Data in Settings → Data to start a new history.")
        case .unavailable:
            title = String(localized: "History Unavailable")
            message = String(localized: "Permission Pulse couldn't open its local database, so it can't track changes. Quit and reopen Permission Pulse; if this keeps happening, use Reset All Data in Settings → Data.")
        }
        return ContentUnavailableView(
            title,
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(message)
        )
    }

    @ViewBuilder
    private func emptyState(_ diff: SnapshotDiffs) -> some View {
        if diff.uncomparedDomains.isEmpty {
            ContentUnavailableView(
                emptyHeadline,
                systemImage: "checkmark.seal.fill",
                description: Text(diff.hasContent
                    ? String(localized: "Every change in this window was dismissed or snoozed.")
                    : String(localized: "Nothing was added, removed, or changed in this window."))
            )
        } else {
            ContentUnavailableView(
                Self.uncomparedHeadline(diff),
                systemImage: "exclamationmark.triangle",
                description: Text(Self.uncomparedDescription(diff))
            )
        }
    }

    static func uncomparedHeadline(_ diff: SnapshotDiffs) -> String {
        diff.comparedDomains.isEmpty
            ? String(localized: "Nothing could be compared")
            : String(localized: "Some history couldn't be compared")
    }

    static func uncomparedDescription(_ diff: SnapshotDiffs) -> String {
        let uncompared = ListFormatter.localizedString(byJoining: diff.uncomparedDomains.map(\.displayName))
        guard !diff.comparedDomains.isEmpty else {
            return String(localized: "\(uncompared) couldn't be compared in this window. The notes above say why.")
        }
        let compared = ListFormatter.localizedString(byJoining: diff.comparedDomains.map(\.displayName))
        return String(localized: "No changes found in \(compared). \(uncompared) couldn't be compared; the notes above say why.")
    }

    private func diffList(_ entries: [DiffEntry]) -> some View {
        List {
            ForEach(HistoryDomain.allCases, id: \.self) { domain in
                let rows = entries.filter { $0.domain == domain }
                if !rows.isEmpty {
                    Section(domain.displayName) {
                        changeRows(rows)
                    }
                }
            }
            if let onMarkAllReviewed, window == .sinceLastReview {
                Section {
                    Button(String(localized: "Mark All Reviewed"), action: onMarkAllReviewed)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .help(String(localized: "Clear these changes; the next visit starts from the latest snapshot"))
                }
            }
        }
        .listStyle(.inset)
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
            Text(String(localized: "Permission Pulse will stop showing this change: \(candidate.summary). You can bring it back in Settings → Data."))
        }
    }

    @ViewBuilder
    private func changeRows(_ rows: [DiffEntry]) -> some View {
        ForEach(rows) { entry in
            let key = DiffEntryKey.key(for: entry)
            ChangeRow(
                kind: entry,
                scopedIdentifiers: btmScopedIdentifiers,
                onDismissForever: {
                    pendingDismiss = PendingDismiss(
                        key: key,
                        summary: ChangeRow.summary(for: entry, scopedIdentifiers: btmScopedIdentifiers)
                    )
                },
                onSnooze: {
                    dismissedStore.snooze(
                        key: key,
                        until: Date().addingTimeInterval(snoozeDuration)
                    )
                }
            )
        }
    }

    private var btmScopedIdentifiers: Set<String> {
        guard let btm = diff?.btm else { return [] }
        return ChangeRow.identifiersInSeveralScopes(btm.added + btm.removed + btm.changed.map(\.after))
    }

    private var noHistoryDescription: String {
        switch window {
        case .sinceLastReview:
            String(localized: "Changes appear here once Permission Pulse has recorded two snapshots.")
        case .lastSevenDays:
            String(localized: "History started less than a week ago. This view fills in once it's a week old.")
        }
    }

    private var emptyHeadline: String {
        switch window {
        case .sinceLastReview: String(localized: "No changes since your last review")
        case .lastSevenDays: String(localized: "No changes in the last 7 days")
        }
    }
}
