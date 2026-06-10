import AppKit
import SwiftUI
import PermissionsCore

struct StaleAppsTabView: View {
    let staleApps: [StaleApp]
    var staleThresholdDays: Int = 90
    @Environment(DismissedStaleAppStore.self) private var dismissedStore

    @State private var pendingSkipCandidate: StaleApp?

    var body: some View {
        // Defensive view-side filter for immediate post-click feedback. The
        // SnapshotCoordinator already filters on the next scan; this catches
        // the gap between click and re-render.
        let visible = staleApps.filter { !dismissedStore.contains(bundleID: $0.app.bundleID) }

        if visible.isEmpty {
            ContentUnavailableView(
                String(localized: "No Stale Apps"),
                systemImage: "checkmark.circle",
                description: Text(String(localized: "Every app with an active grant has been used recently."))
            )
        } else {
            List {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, app in
                    StaleAppRow(app: app)
                        .contextMenu {
                            if app.app.bundlePath != nil {
                                Button(String(localized: "Reveal in Finder")) {
                                    revealInFinder(app: app)
                                }
                            }
                            Button(String(localized: "Skip forever"), role: .destructive) {
                                pendingSkipCandidate = app
                            }
                        }
                }
            }
            .listStyle(.inset)
            .alert(
                String(localized: "Skip this app forever?"),
                isPresented: Binding(
                    get: { pendingSkipCandidate != nil },
                    set: { if !$0 { pendingSkipCandidate = nil } }
                ),
                presenting: pendingSkipCandidate
            ) { candidate in
                Button(String(localized: "Skip"), role: .destructive) {
                    dismissedStore.skipForever(bundleID: candidate.app.bundleID)
                    pendingSkipCandidate = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    pendingSkipCandidate = nil
                }
            } message: { candidate in
                Text(String(localized: "Permission Pulse will stop flagging \(candidate.app.displayName) in Stale Apps. Use Reset All Data in Preferences to un-skip."))
            }
        }
    }

    // AppKit: NSWorkspace reveals the app bundle in Finder (read-only).
    private func revealInFinder(app: StaleApp) {
        guard let url = app.app.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct StaleAppRow: View {
    let app: StaleApp

    var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            AppIconResolver.iconView(for: app.app, size: 28)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(app.app.displayName).ppFont(.body).fontWeight(.medium)
                Text(app.app.bundleID).ppFont(.metadata).foregroundStyle(.secondary)
                Text(servicesLine).ppFont(.metadata).foregroundStyle(.tertiary)
                Text(lastUsedLine).ppFont(.metadata).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, PPSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var servicesLine: String {
        let names = app.grantedServices.map(\.displayName).sorted().joined(separator: ", ")
        return String(localized: "Granted: \(names)")
    }

    private var lastUsedLine: String {
        let dateString = DateFormatter.localizedString(
            from: app.lastUsedDate,
            dateStyle: .medium,
            timeStyle: .none
        )
        let source = app.dateSource == .spotlight
            ? String(localized: "via Spotlight")
            : String(localized: "via file modified")
        return String(localized: "Last used \(dateString) · \(source) · \(app.daysSinceUsed) days ago")
    }
}
