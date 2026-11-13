import AppKit
import SwiftUI
import PermissionsCore

struct StaleAppsTabView: View {
    let staleApps: [StaleApp]
    var staleThresholdDays: Int = 90
    var emptyState: StaleAppsEmptyState = .noneStale(systemLevelOnly: false)
    @Environment(DismissedStaleAppStore.self) private var dismissedStore
    @Environment(AppViewModel.self) private var viewModel

    @State private var pendingSkipCandidate: StableStaleApp?

    var body: some View {
        // Defensive view-side filter for immediate post-click feedback. The
        // SnapshotCoordinator already filters on the next scan; this catches
        // the gap between click and re-render.
        let visible = visibleStaleApps

        if visible.isEmpty {
            ContentUnavailableView(
                emptyState.title,
                systemImage: emptyState.systemImage,
                description: Text(emptyState.description)
            )
        } else {
            List {
                ForEach(visible) { candidate in
                    StaleAppRow(app: candidate.staleApp)
                        .help(String(localized: "Right-click to reveal or skip this app"))
                        .contextMenu {
                            if candidate.staleApp.app.bundlePath != nil {
                                Button(String(localized: "Reveal in Finder")) {
                                    revealInFinder(app: candidate.staleApp)
                                }
                            }
                            Button(String(localized: "Skip forever"), role: .destructive) {
                                pendingSkipCandidate = candidate
                            }
                        }
                        // VoiceOver can't discover a context menu on its own; mirror its actions.
                        .accessibilityActions {
                            if candidate.staleApp.app.bundlePath != nil {
                                Button(String(localized: "Reveal in Finder")) {
                                    revealInFinder(app: candidate.staleApp)
                                }
                            }
                            Button(String(localized: "Skip forever")) {
                                pendingSkipCandidate = candidate
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
                    viewModel.skipStaleAppForever(stableKey: candidate.stableKey, in: dismissedStore)
                    pendingSkipCandidate = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    pendingSkipCandidate = nil
                }
            } message: { candidate in
                Text(String(localized: "Permission Pulse will stop flagging \(candidate.staleApp.app.displayName) in Stale Apps. You can bring it back in Settings → Data."))
            }
        }
    }

    private var visibleStaleApps: [StableStaleApp] {
        var seenKeys = Set<String>()
        return staleApps.compactMap { app in
            guard let stableKey = app.app.stableKey,
                  seenKeys.insert(stableKey).inserted,
                  !dismissedStore.contains(stableKey: stableKey)
            else { return nil }
            return StableStaleApp(stableKey: stableKey, staleApp: app)
        }
    }

    // AppKit: NSWorkspace reveals the app bundle in Finder (read-only).
    private func revealInFinder(app: StaleApp) {
        guard let url = app.app.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct StableStaleApp: Identifiable {
    let stableKey: String
    let staleApp: StaleApp

    var id: String { stableKey }
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
                Text(StaleAppsTabView.dateLine(for: app)).ppFont(.metadata).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, PPSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var servicesLine: String {
        let names = app.grantedServices.map(\.displayName).sorted().joined(separator: ", ")
        return String(localized: "Granted: \(names)")
    }

}

extension StaleAppsTabView {
    /// A modification date is not a use date, so a row whose date came from
    /// the file-system fallback says so.
    static func dateLine(for app: StaleApp) -> String {
        let dateString = DateFormatter.localizedString(
            from: app.lastUsedDate,
            dateStyle: .medium,
            timeStyle: .none
        )
        switch app.dateSource {
        case .spotlight:
            return String(localized: "Last used \(dateString) · via Spotlight · \(app.daysSinceUsed) days ago")
        case .fileSystem:
            return String(localized: "Last modified \(dateString) · \(app.daysSinceUsed) days ago")
        }
    }
}
