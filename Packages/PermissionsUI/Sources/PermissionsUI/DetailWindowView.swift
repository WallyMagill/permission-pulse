// AppKit: NSApp.activate(ignoringOtherApps:) from the Preferences toolbar
// button — SwiftUI does not expose an app-activation primitive.
import AppKit
import SwiftUI
import PermissionsCore
import PermissionsStore

public struct DetailWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel
    private let onRefresh: (() async -> Void)?
    private let onWhatChangedSelected: (() -> Void)?

    @State private var selection: DetailSidebarSelection = .permissions
    @State private var searchText: String = ""

    public init(
        onRefresh: (() async -> Void)? = nil,
        onWhatChangedSelected: (() -> Void)? = nil
    ) {
        self.onRefresh = onRefresh
        self.onWhatChangedSelected = onWhatChangedSelected
    }

    public var body: some View {
        @Bindable var bindableViewModel = viewModel

        NavigationSplitView {
            DetailSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } detail: {
            detailPage
                .toolbar {
                    if let onRefresh {
                        ToolbarItem(placement: .primaryAction) {
                            RefreshToolbarButton {
                                await onRefresh()
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ExportToolbarMenu()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        PreferencesToolbarButton {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "preferences")
                        }
                    }
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: searchPrompt)
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .navigationTitle(String(localized: "Permission Pulse"))
        .sheet(isPresented: $bindableViewModel.showFDASheetOnDetail) {
            FDAGrantSheet()
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { applyPendingRouteIfAny() }
        .onChange(of: viewModel.pendingRoute) { _, _ in applyPendingRouteIfAny() }
        .onChange(of: selection) { _, newSelection in
            // Each time the user lands on Recent Changes — sidebar nav OR menu
            // bar bounce-back — mark the latest snapshot as reviewed so the
            // unreviewed badge clears.
            if newSelection == .recentChanges {
                onWhatChangedSelected?()
            }
            // Reset the search field when changing context; it'd otherwise
            // filter a list the user no longer sees.
            searchText = ""
        }
    }

    @ViewBuilder
    private var detailPage: some View {
        switch selection {
        case .permissions:
            PermissionsDetailPage(searchText: searchText)
        case .launchAgents:
            LaunchAgentsDetailPage(searchText: searchText)
        case .backgroundItems:
            BackgroundItemsDetailPage(searchText: searchText)
        case .recentChanges:
            RecentChangesDetailPage()
        case .staleApps:
            StaleAppsDetailPage(searchText: searchText)
        }
    }

    private var searchPrompt: String {
        switch selection {
        case .permissions: String(localized: "Search permissions")
        case .launchAgents: String(localized: "Search launch agents")
        case .backgroundItems: String(localized: "Search background items")
        case .recentChanges: String(localized: "Search recent changes")
        case .staleApps: String(localized: "Search stale apps")
        }
    }

    private func applyPendingRouteIfAny() {
        guard let route = viewModel.pendingRoute else { return }
        switch route.sidebarItem {
        case .permissions, .overview: selection = .permissions
        case .launchAgents: selection = .launchAgents
        case .backgroundItems: selection = .backgroundItems
        case .recentChanges: selection = .recentChanges
        case .staleApps: selection = .staleApps
        }
        viewModel.pendingRoute = nil
    }
}

// MARK: - Sidebar selection

enum DetailSidebarSelection: Hashable, Sendable {
    case permissions
    case launchAgents
    case backgroundItems
    case recentChanges
    case staleApps
}

// MARK: - Sidebar

// Custom sidebar (not List) so the selected row can render the exact SOLID
// accent-blue rounded rect from the V2 mockup. macOS's default .sidebar list
// selection is too muted and fights the tinted chips.
private struct DetailSidebar: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var selection: DetailSidebarSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    SidebarSection(header: String(localized: "Inventory")) {
                        SidebarButton(
                            target: .permissions,
                            currentSelection: $selection,
                            icon: "lock.fill",
                            tint: PPColor.permissions,
                            title: String(localized: "Permissions"),
                            trailing: .count(viewModel.grants.count)
                        )
                        SidebarButton(
                            target: .launchAgents,
                            currentSelection: $selection,
                            icon: "clock.fill",
                            tint: PPColor.launchAgents,
                            title: String(localized: "Launch Agents"),
                            trailing: .count(viewModel.launchAgents.count)
                        )
                        SidebarButton(
                            target: .backgroundItems,
                            currentSelection: $selection,
                            icon: "square.stack.3d.up.fill",
                            tint: PPColor.backgroundItems,
                            title: String(localized: "Background Items"),
                            trailing: .count(viewModel.btmItems.count)
                        )
                    }
                    SidebarSection(header: String(localized: "Activity")) {
                        SidebarButton(
                            target: .recentChanges,
                            currentSelection: $selection,
                            icon: "clock.arrow.circlepath",
                            tint: PPColor.recentChanges,
                            title: String(localized: "Recent Changes"),
                            trailing: recentTrailing
                        )
                        SidebarButton(
                            target: .staleApps,
                            currentSelection: $selection,
                            icon: "hourglass",
                            tint: PPColor.staleApps,
                            title: String(localized: "Stale Apps"),
                            trailing: .count(viewModel.staleApps.count)
                        )
                    }
                }
                .padding(.horizontal, PPSpacing.sm)
                .padding(.vertical, PPSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            sidebarFooter
        }
    }

    private var recentTrailing: SidebarButton.Trailing {
        let total = viewModel.recentChangeEventCount
        if viewModel.hasUnreviewedChanges && total > 0 {
            return .newBadge(total)
        }
        if total > 0 {
            return .count(total)
        }
        return .none
    }

    private var sidebarFooter: some View {
        HStack(spacing: PPSpacing.sm) {
            ZStack {
                Circle().fill(footerColor.opacity(0.22)).frame(width: 13, height: 13)
                Circle().fill(footerColor).frame(width: 7, height: 7)
            }
            .accessibilityHidden(true)
            Text(footerText)
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PPSpacing.lg)
        .padding(.vertical, PPSpacing.sm)
    }

    private var footerColor: Color {
        if viewModel.tccScanError != nil || viewModel.btmScanError != nil || viewModel.launchAgentScanError != nil { return PPColor.warning }
        return PPColor.success
    }

    private var footerText: String {
        if viewModel.tccScanError != nil || viewModel.btmScanError != nil || viewModel.launchAgentScanError != nil {
            return String(localized: "Needs attention")
        }
        return String(localized: "Up to date")
    }
}

private struct SidebarSection<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            Text(header)
                .ppSectionLabel()
                .padding(.horizontal, PPSpacing.md)
                .padding(.bottom, PPSpacing.xxs)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarButton: View {
    enum Trailing {
        case count(Int)
        case newBadge(Int)
        case none
    }

    let target: DetailSidebarSelection
    @Binding var currentSelection: DetailSidebarSelection
    let icon: String
    let tint: Color
    let title: String
    let trailing: Trailing

    @State private var isHovering = false

    private var isSelected: Bool { currentSelection == target }

    var body: some View {
        Button {
            currentSelection = target
        } label: {
            HStack(spacing: PPSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.24) : tint.opacity(0.16))
                        .frame(width: 20, height: 20)
                    Image(systemName: icon)
                        // Decorative icon inside fixed 20×20 tile — keep fixed size (rule 1)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : tint)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .ppFont(.secondary)
                    .foregroundStyle(isSelected ? Color.white : .primary)
                Spacer(minLength: PPSpacing.xs)
                trailingView
            }
            .padding(.horizontal, PPSpacing.sm)
            .padding(.vertical, PPSpacing.xs)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                .fill(Color.accentColor)
        } else if isHovering {
            RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .count(let n):
            Text("\(n)")
                .ppFont(.metadata)
                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : .secondary)
                .monospacedDigit()
        case .newBadge(let n):
            Text("\(n)")
                .ppFont(.badge)
                .foregroundStyle(isSelected ? Color.orange : Color.white)
                .padding(.horizontal, PPSpacing.sm)
                .padding(.vertical, PPSpacing.xxs)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.orange)
                )
                .monospacedDigit()
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Detail page scaffold

private struct DetailPageScaffold<Content: View>: View {
    let title: String
    var inlineMeta: String? = nil
    let subtitle: String?
    var dataSource: AppViewModel.DataSource? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: PPSpacing.md) {
                Text(title)
                    .ppFont(.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                if dataSource == .mock {
                    MockBadge()
                }
                if let inlineMeta {
                    Text(inlineMeta)
                        .ppFont(.secondary)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.top, PPSpacing.lg)
            .padding(.bottom, PPSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    if let subtitle {
                        Text(subtitle)
                            .ppFont(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    content()
                }
                .padding(.horizontal, PPSpacing.xl)
                .padding(.bottom, PPSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Permissions page

private struct PermissionsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String

    var body: some View {
        DetailPageScaffold(
            title: String(localized: "Permissions"),
            inlineMeta: inlineMeta,
            subtitle: viewModel.grants.isEmpty
                ? nil
                : String(localized: "Tap a row to see what each grant unlocks and how it was given."),
            dataSource: viewModel.tccDataSource
        ) {
            if let error = viewModel.tccScanError, isSchemaIssue(error) {
                SchemaMismatchBanner(error: error, domain: .tcc)
            }

            if ScanState.showsScanningPlaceholder(
                isScanning: viewModel.scanInProgress,
                isEmpty: viewModel.grants.isEmpty,
                hasError: viewModel.tccScanError != nil,
                isSearching: !searchText.isEmpty
            ) {
                ScanningPlaceholder()
            } else if filteredGrants.isEmpty && !searchText.isEmpty {
                EmptySearchView(query: searchText)
            } else {
                PermissionsSection(
                    grants: filteredGrants,
                    dataSource: viewModel.tccDataSource,
                    error: viewModel.tccScanError,
                    showsHeader: false
                )
            }
        }
    }

    private var filteredGrants: [PermissionGrant] {
        if searchText.isEmpty { return viewModel.grants }
        let q = searchText.lowercased()
        return viewModel.grants.filter { grant in
            grant.app.displayName.lowercased().contains(q)
                || grant.app.bundleID.lowercased().contains(q)
                || grant.service.displayName.lowercased().contains(q)
        }
    }

    private var inlineMeta: String? {
        if viewModel.grants.isEmpty { return nil }
        let appCount = Set(viewModel.grants.map(\.app.bundleID)).count
        let serviceCount = Set(viewModel.grants.map(\.service)).count
        return String(localized: "\(appCount) apps · \(serviceCount) services")
    }
}

// MARK: - Launch Agents page

private struct LaunchAgentsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String

    var body: some View {
        DetailPageScaffold(title: String(localized: "Launch Agents"), subtitle: subtitle, dataSource: viewModel.launchAgentsDataSource) {
            if let error = viewModel.launchAgentScanError {
                VStack(spacing: PPSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        // Decorative hero icon — keep fixed size (rule 1)
                        .font(.system(size: 36))
                        .foregroundStyle(PPColor.warning)
                        .accessibilityHidden(true)
                    Text(String(localized: "Couldn't read Launch Agents"))
                        .ppFont(.cardHeader)
                    Text(error.errorDescription ?? String(localized: "An error occurred reading the LaunchAgents directories."))
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PPSpacing.xxl)
            } else if ScanState.showsScanningPlaceholder(
                isScanning: viewModel.scanInProgress,
                isEmpty: viewModel.launchAgents.isEmpty,
                hasError: false, // the error block above already owns that surface
                isSearching: !searchText.isEmpty
            ) {
                ScanningPlaceholder()
            } else {
                if filteredItems.isEmpty && !searchText.isEmpty {
                    EmptySearchView(query: searchText)
                } else {
                    LaunchAgentsSection(
                        items: filteredItems,
                        dataSource: viewModel.launchAgentsDataSource,
                        showsHeader: false
                    )
                }
            }
        }
    }

    private var filteredItems: [LaunchAgentItem] {
        if searchText.isEmpty { return viewModel.launchAgents }
        let q = searchText.lowercased()
        return viewModel.launchAgents.filter { item in
            item.label.lowercased().contains(q)
                || (item.programPath?.lowercased().contains(q) ?? false)
        }
    }

    private var subtitle: String? {
        if viewModel.launchAgents.isEmpty { return nil }
        return String(localized: "\(viewModel.launchAgents.count) agents across user and system scopes")
    }
}

// MARK: - Background Items page

private struct BackgroundItemsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String

    var body: some View {
        DetailPageScaffold(title: String(localized: "Background Items"), subtitle: subtitle, dataSource: viewModel.btmDataSource) {
            if let error = viewModel.btmScanError, isSchemaIssue(error) {
                SchemaMismatchBanner(error: error, domain: .btm)
            }

            if ScanState.showsScanningPlaceholder(
                isScanning: viewModel.scanInProgress,
                isEmpty: viewModel.btmItems.isEmpty,
                hasError: viewModel.btmScanError != nil,
                isSearching: !searchText.isEmpty
            ) {
                ScanningPlaceholder()
            } else if filteredItems.isEmpty && !searchText.isEmpty {
                EmptySearchView(query: searchText)
            } else {
                BackgroundItemsSection(
                    items: filteredItems,
                    dataSource: viewModel.btmDataSource,
                    error: viewModel.btmScanError,
                    showsHeader: false
                )
            }
        }
    }

    private var filteredItems: [BTMItem] {
        if searchText.isEmpty { return viewModel.btmItems }
        let q = searchText.lowercased()
        return viewModel.btmItems.filter { item in
            item.name.lowercased().contains(q)
                || (item.developerName?.lowercased().contains(q) ?? false)
                || (item.bundleIdentifier?.lowercased().contains(q) ?? false)
                || item.identifier.lowercased().contains(q)
        }
    }

    private var subtitle: String? {
        if viewModel.btmItems.isEmpty { return nil }
        let enabled = viewModel.btmItems.filter { $0.disposition == .enabled }.count
        return String(localized: "\(viewModel.btmItems.count) items · \(enabled) enabled")
    }
}

// MARK: - Recent Changes page

private struct RecentChangesDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var window: RecentWindow = .yesterday

    var body: some View {
        DetailPageScaffold(title: String(localized: "Recent Changes"), subtitle: nil) {
            Picker("", selection: $window) {
                Text(String(localized: "Yesterday")).tag(RecentWindow.yesterday)
                Text(String(localized: "Last 7 days")).tag(RecentWindow.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Change window"))
            .padding(.bottom, 4)

            switch window {
            case .yesterday:
                DiffTabView(
                    diff: viewModel.latestDiffYesterday,
                    windowLabel: .yesterday,
                    snapshotStoreUnavailable: viewModel.snapshotStoreUnavailable,
                    diffUnavailable: viewModel.diffUnavailable
                )
            case .week:
                DiffTabView(
                    diff: viewModel.latestDiffWeek,
                    windowLabel: .lastWeek,
                    snapshotStoreUnavailable: viewModel.snapshotStoreUnavailable,
                    diffUnavailable: viewModel.diffUnavailable
                )
            }
        }
    }
}

private enum RecentWindow: Hashable {
    case yesterday
    case week
}

// MARK: - Stale Apps page

private struct StaleAppsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String

    var body: some View {
        DetailPageScaffold(title: String(localized: "Stale Apps"), subtitle: subtitle) {
            if filteredApps.isEmpty && !searchText.isEmpty {
                EmptySearchView(query: searchText)
            } else {
                StaleAppsTabView(staleApps: filteredApps, staleThresholdDays: viewModel.staleThresholdDays)
            }
        }
    }

    private var filteredApps: [StaleApp] {
        if searchText.isEmpty { return viewModel.staleApps }
        let q = searchText.lowercased()
        return viewModel.staleApps.filter { app in
            app.app.displayName.lowercased().contains(q)
                || app.app.bundleID.lowercased().contains(q)
        }
    }

    private var subtitle: String? {
        if viewModel.staleApps.isEmpty { return nil }
        return String(localized: "Apps with active grants you haven't used in \(viewModel.staleThresholdDays)+ days")
    }
}

// MARK: - Helpers

private struct EmptySearchView: View {
    let query: String

    var body: some View {
        VStack(spacing: PPSpacing.sm) {
            Image(systemName: "magnifyingglass")
                // Decorative hero icon — keep fixed size (rule 1)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(String(localized: "No matches for \"\(query)\""))
                .ppFont(.cardHeader)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.xxl)
    }
}

private func isSchemaIssue(_ error: ScannerError) -> Bool {
    switch error {
    case .schemaMismatch, .unsupportedOnThisOS: true
    default: false
    }
}

// Borderless toolbar refresh button — replaces the default pill-shaped button
// macOS would render. Subtle hover background and a quarter-turn nudge while
// the refresh task is running.
private struct RefreshToolbarButton: View {
    let action: () async -> Void

    @State private var isHovering = false
    @State private var isRefreshing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !isRefreshing else { return }
            Task {
                isRefreshing = true
                await action()
                isRefreshing = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                )
                .rotationEffect(.degrees(isRefreshing && !reduceMotion ? 360 : 0))
                .animation(
                    isRefreshing && !reduceMotion
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default,
                    value: isRefreshing
                )
                .opacity(reduceMotion && isRefreshing ? 0.45 : 1.0)
                .accessibilityLabel(isRefreshing ? String(localized: "Refreshing") : String(localized: "Refresh"))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(String(localized: "Refresh"))
    }
}

private struct PreferencesToolbarButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(String(localized: "Preferences"))
        .keyboardShortcut(",", modifiers: [.command])
    }
}
