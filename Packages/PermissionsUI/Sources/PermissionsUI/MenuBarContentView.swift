import AppKit
import SwiftUI
import PermissionsCore
import PermissionsStore

public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel
    private let onShowWelcome: (() -> Void)?
    private let onRescan: (() -> Void)?

    public init(
        onShowWelcome: (() -> Void)? = nil,
        onRescan: (() -> Void)? = nil
    ) {
        self.onShowWelcome = onShowWelcome
        self.onRescan = onRescan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, PPSpacing.lg)
                .padding(.top, PPSpacing.lg)
                .padding(.bottom, PPSpacing.md)

            if !isCleanAttention {
                attentionBanner
                    .padding(.horizontal, PPSpacing.md)
                    .padding(.bottom, PPSpacing.sm)
            }

            overviewSection

            if !recentEvents.isEmpty {
                recentSection
            }

            Divider()
                .padding(.horizontal, PPSpacing.sm)
                .padding(.top, PPSpacing.sm)
                .padding(.bottom, PPSpacing.xs)

            footer
                .padding(.horizontal, PPSpacing.xs)
                .padding(.bottom, PPSpacing.sm)
        }
        .frame(width: 320)
        .ppDropdownDynamicTypeClamp()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: PPSpacing.md) {
            BrandBadge()
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(String(localized: "Permission Pulse"))
                    .ppFont(.cardHeader)
                HStack(spacing: PPSpacing.sm) {
                    PulseDot(tint: pulseTint)
                    Text(headerStatusText)
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var pulseTint: Color {
        if viewModel.scanInProgress { return PPColor.permissions }
        return isCleanAttention ? PPColor.success : PPColor.warning
    }

    private var headerStatusText: String {
        if viewModel.scanInProgress {
            return String(localized: "Scanning…")
        }
        switch viewModel.attentionState {
        case .clean: return String(localized: "Watching for changes")
        case .fdaDenied, .btmOnlyFDADenied: return String(localized: "Action needed")
        case .schemaMismatch: return String(localized: "Schema mismatch")
        case .launchAgentError: return String(localized: "Action needed")
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
                tint: PPColor.permissions,
                title: String(localized: "Permissions"),
                count: viewModel.grants.count
            )
            StatRow(
                icon: "clock.fill",
                tint: PPColor.launchAgents,
                title: String(localized: "Launch Agents"),
                count: viewModel.launchAgents.count
            )
            StatRow(
                icon: "square.stack.3d.up.fill",
                tint: PPColor.backgroundItems,
                title: String(localized: "Background Items"),
                count: viewModel.btmItems.count
            )
            if let risk = PermissionRiskSummary.line(for: viewModel.grants) {
                HStack(spacing: PPSpacing.sm) {
                    Image(systemName: "exclamationmark.shield")
                        .ppFont(.badge)
                        .foregroundStyle(PPColor.warning)
                        .accessibilityHidden(true)
                    Text(risk)
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Elevated access: \(risk)"))
                .padding(.horizontal, PPSpacing.lg)
                .padding(.top, PPSpacing.xs)
            }
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
                trailingTint: PPColor.recentChanges,
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

    private var isCleanAttention: Bool {
        viewModel.attentionState == .clean
    }

    @ViewBuilder
    private var attentionBanner: some View {
        switch viewModel.attentionState {
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
        case .launchAgentError:
            AttentionBanner(
                title: String(localized: "Launch Agents couldn't be read"),
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

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let onRescan {
                MenuRowButton(
                    icon: "arrow.clockwise",
                    title: String(localized: "Rescan Now"),
                    shortcutKey: "r",
                    shortcutDisplay: "⌘R"
                ) {
                    onRescan()
                }
                .disabled(viewModel.scanInProgress)
            }

            MenuRowButton(
                icon: "clock.arrow.circlepath",
                iconTint: .accentColor,
                title: String(localized: "What Changed"),
                shortcutKey: "w",
                shortcutDisplay: "⌘W",
                showsChangeDot: viewModel.hasUnreviewedChanges
            ) {
                viewModel.pendingRoute = .recentChanges
                activateAndOpen("detail")
            }

            MenuRowButton(
                icon: "arrow.up.forward.square",
                title: String(localized: "Open Permission Pulse"),
                shortcutKey: "o",
                shortcutDisplay: "⌘O"
            ) {
                viewModel.pendingRoute = .permissions(selectAppKey: nil)
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

            if let onShowWelcome {
                MenuRowButton(
                    icon: "info.circle",
                    title: String(localized: "Welcome & About")
                ) {
                    onShowWelcome()
                }
            }

            // tight divider inset (between tokens)
            Divider()
                .padding(.horizontal, PPSpacing.sm)
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
        case .added:   PPColor.success
        case .removed: PPColor.danger
        case .changed: PPColor.warning
        }
    }
}

// MARK: - Subviews

private struct BrandBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PPRadius.medium, style: .continuous)
            .fill(PPColor.brandGradient)
            .frame(width: 36, height: 36)
            .overlay {
                // Fixed size: brand mark sized to its 36×36 tile, not a text role.
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .shadow(color: PPColor.permissions.opacity(0.35), radius: 5, y: 1)
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
        .accessibilityHidden(true)
    }
}

private struct SectionLabel: View {
    let title: String
    let trailing: String?
    var trailingTint: Color = .secondary
    var trailingBold: Bool = false

    var body: some View {
        HStack(spacing: PPSpacing.sm) {
            Text(title)
                .ppSectionLabel()
            Spacer(minLength: PPSpacing.sm)
            if let trailing {
                Text(trailing)
                    .ppFont(trailingBold ? .badge : .metadata)
                    .foregroundStyle(trailingTint)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, PPSpacing.lg)
        .padding(.top, PPSpacing.md)
        .padding(.bottom, PPSpacing.xs)
    }
}

private struct StatRow: View {
    let icon: String
    let tint: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
            Text(title)
                .ppFont(.body)
            Spacer(minLength: PPSpacing.sm)
            Text("\(count)")
                .ppFont(.body)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, PPSpacing.lg)
        .padding(.vertical, PPSpacing.xs)
    }
}

private struct ActivityRow: View {
    let event: RecentEvent

    var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            Circle()
                .fill(event.markerColor)
                .frame(width: 6, height: 6)
                // optical baseline alignment with the first text line
                .padding(.top, 7)
                .accessibilityHidden(true)
            (Text(event.strong).bold() + Text(" · \(event.descriptor)"))
                .ppFont(.secondary)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PPSpacing.xs)
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, PPSpacing.lg)
        .padding(.vertical, PPSpacing.xs)
    }
}

private struct AttentionBanner: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                            .fill(PPColor.warning)
                            .shadow(color: PPColor.warning.opacity(0.35), radius: 3, y: 1)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .ppFont(.cardHeader)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: PPSpacing.xs)
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(PPColor.warning)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PPSpacing.md)
            .padding(.vertical, PPSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: PPRadius.medium, style: .continuous)
                    .fill(PPColor.warning.opacity(isHovering ? 0.22 : 0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.medium, style: .continuous)
                    .strokeBorder(PPColor.warning.opacity(0.22), lineWidth: 1)
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
    var shortcutKey: KeyEquivalent? = nil
    var shortcutDisplay: String? = nil
    var showsChangeDot: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(iconTint)
                    .accessibilityHidden(true)
                Text(title)
                    .ppFont(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: PPSpacing.sm)
                if showsChangeDot {
                    PulseDot(tint: PPColor.warning)
                }
                if let shortcutDisplay {
                    Text(shortcutDisplay)
                        .ppFont(.metadata)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, PPSpacing.sm)
            .padding(.vertical, PPSpacing.sm)
            .background {
                RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .modifier(OptionalShortcut(key: shortcutKey))
    }
}

/// Applies `.keyboardShortcut` only when a key is present — `MenuRowButton`
/// rows like Welcome & About have no shortcut.
private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: [.command])
        } else {
            content
        }
    }
}
