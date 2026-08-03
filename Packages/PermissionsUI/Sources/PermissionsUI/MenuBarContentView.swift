import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onShowWelcome: (() -> Void)?
    private let onRescan: (() -> Void)?

    public init(onShowWelcome: (() -> Void)? = nil, onRescan: (() -> Void)? = nil) {
        self.onShowWelcome = onShowWelcome
        self.onRescan = onRescan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, PPSpacing.lg)
                .padding(.top, PPSpacing.md)
                .padding(.bottom, PPSpacing.sm)

            Divider().padding(.horizontal, PPSpacing.sm)

            statusRows
                .padding(.vertical, PPSpacing.xs)
                .padding(.horizontal, PPSpacing.xs)

            Divider().padding(.horizontal, PPSpacing.sm)

            footer
                .padding(.horizontal, PPSpacing.xs)
                .padding(.vertical, PPSpacing.xs)
        }
        .frame(width: 320)
        .ppDropdownDynamicTypeClamp()
    }

    private var header: some View {
        HStack(spacing: PPSpacing.sm) {
            Text(String(localized: "Permission Pulse"))
                .ppFont(.cardHeader)
            if viewModel.tccDataSource == .mock || viewModel.btmDataSource == .mock
                || viewModel.launchAgentsDataSource == .mock {
                MockBadge()
            }
            Spacer(minLength: 0)
            if viewModel.scanInProgress {
                HStack(spacing: PPSpacing.xs) {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "Scanning…"))
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(currentRows) { row in
                StatusRowButton(row: row) {
                    viewModel.pendingRoute = row.route
                    activateAndOpen("detail")
                }
            }
        }
        // The window-style dropdown stays live while open: a call ending or a
        // rescan finishing can add/remove rows mid-interaction. Track the
        // reflow so rows don't pop and shift the footer under the cursor.
        .animation(reduceMotion ? nil : .default, value: currentRows)
    }

    private var currentRows: [DropdownStatusRow] {
        DropdownStatusBuilder.rows(
            attention: viewModel.attentionState,
            micInUse: viewModel.micInUse,
            cameraInUse: viewModel.cameraInUse,
            changeCount: viewModel.recentChangeEventCount,
            hasUnreviewedChanges: viewModel.hasUnreviewedChanges,
            staleCount: viewModel.staleApps.count,
            appCount: Set(viewModel.grants.map(\.appKey)).count
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            MenuRowButton(
                icon: "arrow.up.forward.square",
                title: String(localized: "Open Permission Pulse"),
                shortcutKey: "o", shortcutDisplay: "⌘O"
            ) {
                viewModel.pendingRoute = .overview
                activateAndOpen("detail")
            }
            if let onRescan {
                MenuRowButton(
                    icon: "arrow.clockwise",
                    title: String(localized: "Rescan Now"),
                    shortcutKey: "r", shortcutDisplay: "⌘R"
                ) { onRescan() }
                .disabled(viewModel.scanInProgress)
            }
            MenuRowButton(
                icon: "gearshape",
                title: String(localized: "Settings…"),
                shortcutKey: ",", shortcutDisplay: "⌘,"
            ) { activateAndOpen("preferences") }
            if let onShowWelcome {
                MenuRowButton(
                    icon: "info.circle",
                    title: String(localized: "Welcome & About")
                ) { onShowWelcome() }
            }
            Divider().padding(.horizontal, PPSpacing.sm).padding(.vertical, 3)
            MenuRowButton(
                icon: "power",
                title: String(localized: "Quit"),
                shortcutKey: "q", shortcutDisplay: "⌘Q"
            ) { NSApplication.shared.terminate(nil) }
        }
    }

    // Bring PP to the foreground first, then open/raise the target window.
    // Opening from the menu bar without this leaves PP in the background even
    // though the window is now key — feels disorienting because nothing
    // visually responds to the click.
    private func activateAndOpen(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

// MARK: - Status row

/// One glance row: status icon, copy, trailing chevron. Hover + click like a
/// native menu row; every row is a deep link.
private struct StatusRowButton: View {
    let row: DropdownStatusRow
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: symbolName)
                    // .caption matches the previous fixed 12pt at the default
                    // size but tracks Dynamic Type alongside the row's text.
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(row.title)
                    .ppFont(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    // Digit-morph only where the copy actually carries a count.
                    .contentTransition(isCountRow ? .numericText() : .opacity)
                    .animation(reduceMotion ? nil : .default, value: row.title)
                Spacer(minLength: PPSpacing.xs)
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
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
        .accessibilityHint(destinationHint)
    }

    /// VoiceOver mirror of the deep link each row follows; sighted users get
    /// the same routing information from the row copy and chevron.
    private var destinationHint: String {
        switch row.route {
        case .overview:
            String(localized: "Opens the Overview in Permission Pulse")
        case .permissions:
            String(localized: "Opens Permissions in Permission Pulse")
        case .launchAgents:
            String(localized: "Opens Launch Agents in Permission Pulse")
        case .backgroundItems:
            String(localized: "Opens Background Items in Permission Pulse")
        case .recentChanges:
            String(localized: "Opens Recent Changes in Permission Pulse")
        case .staleApps:
            String(localized: "Opens Stale Apps in Permission Pulse")
        }
    }

    private var isCountRow: Bool {
        switch row.kind {
        case .changes, .stale, .allClear: true
        case .attention, .media: false
        }
    }

    private var symbolName: String {
        switch row.kind {
        case .attention: "exclamationmark.triangle.fill"
        case .media(_, true): "video.fill"
        case .media: "mic.fill"
        case .changes: "clock.arrow.circlepath"
        case .stale: "hourglass"
        case .allClear: "checkmark.shield"
        }
    }

    private var iconColor: Color {
        switch row.kind {
        case .attention: PPColor.warning
        case .media: PPColor.danger
        case .changes: PPColor.recentChanges
        case .stale: PPColor.staleApps
        case .allClear: PPColor.success
        }
    }
}

// MARK: - Footer button

private struct MenuRowButton: View {
    let icon: String
    var iconTint: Color = .secondary
    let title: String
    var shortcutKey: KeyEquivalent? = nil
    var shortcutDisplay: String? = nil
    let action: () -> Void

    @State private var isHovering = false
    // `.plain` + hardcoded foreground styles defeat the automatic disabled
    // dimming, so a disabled row (Rescan Now mid-scan) would still look and
    // hover-highlight like a live one.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: icon)
                    // .footnote matches the previous fixed 13pt at the default
                    // size but tracks Dynamic Type alongside the row's text.
                    .font(.system(.footnote, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(iconTint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                Text(title)
                    .ppFont(.body)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                Spacer(minLength: PPSpacing.sm)
                if let shortcutDisplay {
                    Text(shortcutDisplay)
                        .ppFont(.metadata)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        // The real shortcut is exposed via .keyboardShortcut;
                        // VoiceOver shouldn't read the display glyphs ("⌘R").
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PPSpacing.sm)
            .padding(.vertical, PPSpacing.sm)
            .background {
                RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.primary.opacity(0.06) : .clear)
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
