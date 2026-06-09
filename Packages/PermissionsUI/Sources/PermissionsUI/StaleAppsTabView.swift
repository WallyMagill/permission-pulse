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
            empty
        } else {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text(String(localized: "Apps with active grants you haven't used in \(staleThresholdDays)+ days"))
                    .ppFont(.secondary)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Use the ⋯ menu on a row to skip an app you don't want flagged."))
                    .ppFont(.metadata)
                    .foregroundStyle(.tertiary)
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, app in
                        StaleAppRow(
                            app: app,
                            onSkipForever: { pendingSkipCandidate = app }
                        )
                        .padding(.vertical, PPSpacing.sm)
                        .padding(.horizontal, PPSpacing.md)
                        if index < visible.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .vibrancyCard()
            }
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

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(String(localized: "No stale apps")).ppFont(.cardHeader)
            Text(String(localized: "Every app with an active grant has been used recently."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

private struct StaleAppRow: View {
    let app: StaleApp
    var onSkipForever: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            icon
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(app.app.displayName).ppFont(.body).fontWeight(.medium)
                Text(app.app.bundleID).ppFont(.metadata).foregroundStyle(.secondary)
                Text(servicesLine).ppFont(.metadata).foregroundStyle(.tertiary)
                Text(lastUsedLine).ppFont(.tertiary).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let onSkipForever {
                Menu {
                    if app.app.bundlePath != nil {
                        Button(String(localized: "Reveal in Finder")) { revealInFinder() }
                    }
                    Button(String(localized: "Skip forever")) { onSkipForever() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .ppFont(.body)
                        .foregroundStyle(.tertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(String(localized: "Options"))
                .accessibilityHint(app.app.bundlePath != nil
                    ? String(localized: "Reveal in Finder or skip this app")
                    : String(localized: "Skip this app"))
            }
        }
    }

    private var icon: some View {
        AppIconResolver.iconView(for: app.app, size: 36)
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

    // AppKit: NSWorkspace reveals the app bundle in Finder (read-only).
    private func revealInFinder() {
        guard let url = app.app.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
