import AppKit
import SwiftUI
import PermissionsCore
import PermissionsStore

public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if !isCleanAttention {
                attentionBanner
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            overviewSection

            if !recentEvents.isEmpty {
                recentSection
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

            footer
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            BrandBadge()
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Permission Pulse"))
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    PulseDot(tint: pulseTint)
                    Text(headerStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var pulseTint: Color {
        isCleanAttention ? .green : .orange
    }

    private var headerStatusText: String {
        switch attentionState {
        case .clean: String(localized: "Watching for changes")
        case .fdaDenied, .btmOnlyFDADenied: String(localized: "Action needed")
        case .schemaMismatch: String(localized: "Schema mismatch")
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(
                title: String(localized: "Overview"),
                trailing: String(localized: "\(totalItemCount) items")
            )
            StatRow(
                icon: "lock.fill",
                tint: .blue,
                title: String(localized: "Permissions"),
                count: viewModel.grants.count
            )
            StatRow(
                icon: "clock.fill",
                tint: .purple,
                title: String(localized: "Launch Agents"),
                count: viewModel.launchAgents.count
            )
            StatRow(
                icon: "square.stack.3d.up.fill",
                tint: .teal,
                title: String(localized: "Background Items"),
                count: viewModel.btmItems.count
            )
        }
    }

    private var totalItemCount: Int {
        viewModel.grants.count + viewModel.launchAgents.count + viewModel.btmItems.count
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(
                title: String(localized: "Recent"),
                trailing: String(localized: "\(recentEvents.count) new"),
                trailingTint: .orange,
                trailingBold: true
            )
            ForEach(recentEvents.prefix(2)) { event in
                ActivityRow(event: event)
            }
        }
    }

    private var recentEvents: [RecentEvent] {
        let primary = viewModel.latestDiffYesterday
        let fallback = viewModel.latestDiffWeek
        let diff: SnapshotDiffs? = {
            if let primary, primary.hasContent { return primary }
            return fallback
        }()
        guard let diff else { return [] }

        var events: [RecentEvent] = []

        for grant in diff.tcc.added {
            events.append(
                RecentEvent(
                    id: "tcc.add.\(grant.id)",
                    kind: .added,
                    strong: grant.app.displayName,
                    descriptor: String(localized: "\(grant.service.displayName) granted")
                )
            )
        }
        for grant in diff.tcc.removed {
            events.append(
                RecentEvent(
                    id: "tcc.rem.\(grant.id)",
                    kind: .removed,
                    strong: grant.app.displayName,
                    descriptor: String(localized: "\(grant.service.displayName) removed")
                )
            )
        }
        for agent in diff.launchAgents.added {
            events.append(
                RecentEvent(
                    id: "la.add.\(agent.id)",
                    kind: .added,
                    strong: agent.label,
                    descriptor: String(localized: "Launch agent added")
                )
            )
        }
        for agent in diff.launchAgents.removed {
            events.append(
                RecentEvent(
                    id: "la.rem.\(agent.id)",
                    kind: .removed,
                    strong: agent.label,
                    descriptor: String(localized: "Launch agent removed")
                )
            )
        }
        for item in diff.btm.added {
            events.append(
                RecentEvent(
                    id: "btm.add.\(item.id)",
                    kind: .added,
                    strong: item.name,
                    descriptor: String(localized: "Background item added")
                )
            )
        }
        for item in diff.btm.removed {
            events.append(
                RecentEvent(
                    id: "btm.rem.\(item.id)",
                    kind: .removed,
                    strong: item.name,
                    descriptor: String(localized: "Background item removed")
                )
            )
        }

        return events
    }

    // MARK: - Attention

    private enum AttentionState {
        case fdaDenied
        case btmOnlyFDADenied
        case schemaMismatch
        case clean
    }

    private var attentionState: AttentionState {
        let tccDenied = isPermissionDenied(viewModel.tccScanError)
        let btmDenied = isPermissionDenied(viewModel.btmScanError)
        if tccDenied { return .fdaDenied }
        if btmDenied { return .btmOnlyFDADenied }
        if isSchemaIssue(viewModel.tccScanError) || isSchemaIssue(viewModel.btmScanError) {
            return .schemaMismatch
        }
        return .clean
    }

    private var isCleanAttention: Bool {
        if case .clean = attentionState { true } else { false }
    }

    @ViewBuilder
    private var attentionBanner: some View {
        switch attentionState {
        case .fdaDenied:
            AttentionBanner(
                title: String(localized: "Full Disk Access needed"),
                subtitle: String(localized: "Required to scan TCC permissions"),
                action: presentFDASheet
            )
        case .btmOnlyFDADenied:
            AttentionBanner(
                title: String(localized: "FDA needed for background items"),
                subtitle: String(localized: "Tap to grant access"),
                action: presentFDASheet
            )
        case .schemaMismatch:
            AttentionBanner(
                title: String(localized: "Schema mismatch detected"),
                subtitle: String(localized: "Open for details"),
                action: { activateAndOpen("detail") }
            )
        case .clean:
            EmptyView()
        }
    }

    private func presentFDASheet() {
        viewModel.showFDASheetOnDetail = true
        activateAndOpen("detail")
    }

    // Bring PP to the foreground first, then open/raise the target window.
    // Opening from the menu bar without this leaves PP in the background even
    // though the window is now key — feels disorienting because nothing
    // visually responds to the click.
    private func activateAndOpen(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func isPermissionDenied(_ error: ScannerError?) -> Bool {
        if case .permissionDenied = error { true } else { false }
    }

    private func isSchemaIssue(_ error: ScannerError?) -> Bool {
        switch error {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            MenuRowButton(
                icon: "clock.arrow.circlepath",
                iconTint: .accentColor,
                title: String(localized: "What Changed"),
                shortcutKey: "w",
                shortcutDisplay: "⌘W",
                showsChangeDot: viewModel.hasUnreviewedChanges
            ) {
                viewModel.pendingDetailMode = .whatChanged
                activateAndOpen("detail")
            }

            MenuRowButton(
                icon: "arrow.up.forward.square",
                title: String(localized: "Open Permission Pulse"),
                shortcutKey: "o",
                shortcutDisplay: "⌘O"
            ) {
                viewModel.pendingDetailMode = .current
                activateAndOpen("detail")
            }

            MenuRowButton(
                icon: "gearshape.fill",
                title: String(localized: "Preferences…"),
                shortcutKey: ",",
                shortcutDisplay: "⌘,"
            ) {
                activateAndOpen("preferences")
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

            MenuRowButton(
                icon: "power",
                title: String(localized: "Quit"),
                shortcutKey: "q",
                shortcutDisplay: "⌘Q"
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Models

private struct RecentEvent: Identifiable {
    enum Kind {
        case added
        case removed
        case changed
    }

    let id: String
    let kind: Kind
    let strong: String
    let descriptor: String

    var markerColor: Color {
        switch kind {
        case .added:   .green
        case .removed: .red
        case .changed: .orange
        }
    }
}

// MARK: - Subviews

private struct BrandBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.blue.opacity(0.35), radius: 5, y: 1)
    }
}

private struct PulseDot: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: 13, height: 13)
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let trailing: String?
    var trailingTint: Color = .secondary
    var trailingBold: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: trailingBold ? .semibold : .regular))
                    .foregroundStyle(trailingTint)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct StatRow: View {
    let icon: String
    let tint: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

private struct ActivityRow: View {
    let event: RecentEvent

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(event.markerColor)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            (Text(event.strong).bold() + Text(" · \(event.descriptor)"))
                .font(.system(size: 12.5))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

private struct AttentionBanner: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange)
                            .shadow(color: .orange.opacity(0.35), radius: 3, y: 1)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(isHovering ? 0.22 : 0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct MenuRowButton: View {
    let icon: String
    var iconTint: Color = .secondary
    let title: String
    let shortcutKey: KeyEquivalent
    let shortcutDisplay: String
    var showsChangeDot: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(iconTint)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if showsChangeDot {
                    PulseDot(tint: .orange)
                }
                Text(shortcutDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .keyboardShortcut(shortcutKey, modifiers: [.command])
    }
}
