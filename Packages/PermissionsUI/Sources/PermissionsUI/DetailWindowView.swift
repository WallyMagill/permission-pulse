import AppKit // AppKit: NSApp.activate before openWindow so the Preferences window actually fronts.
import SwiftUI
import PermissionsCore
import PermissionsStore

public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    private let onRefresh: (() async -> Void)?
    private let onWhatChangedSelected: (() -> Void)?

    @State private var section: SidebarItem? = .overview
    @State private var inspectorSelection: InspectorSelection?
    @State private var isInspectorPresented = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var isApplyingRoute = false

    public init(
        onRefresh: (() async -> Void)? = nil,
        onWhatChangedSelected: (() -> Void)? = nil
    ) {
        self.onRefresh = onRefresh
        self.onWhatChangedSelected = onWhatChangedSelected
    }

    public var body: some View {
        NavigationSplitView {
            searchableSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailPage
                .navigationTitle(String(localized: "Permission Pulse"))
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorPanel(selection: inspectorSelection)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
        }
        // Toolbar lives on the NavigationSplitView, not the detail content.
        // The detail is a per-section switch whose identity changes on every
        // tab switch, so hosting the toolbar there made SwiftUI re-establish
        // the items each switch — animating the trailing buttons in. Anchoring
        // it to the stable split view keeps the items put across tab switches
        // and inspector toggles (no re-insertion animation, no transient ghost).
        .toolbar { toolbarContent }
        .frame(minWidth: 760, minHeight: 480)
        .background(windowShortcuts)
        .onAppear { applyPendingRouteIfAny() }
        .onChange(of: viewModel.pendingRoute) { _, _ in applyPendingRouteIfAny() }
        .onChange(of: section) { _, newSection in
            // Landing on Recent Changes — via sidebar or a menu-bar route —
            // marks the latest snapshot reviewed so the unreviewed badge clears.
            if newSection == .recentChanges { onWhatChangedSelected?() }
            // Reset per-context state: the search field and any inspector
            // selection would otherwise dangle into a section that can't show them.
            searchText = ""
            if isApplyingRoute {
                // Route-driven change: keep the pre-selected inspector item.
                isApplyingRoute = false
            } else {
                inspectorSelection = nil
            }
        }
        .onChange(of: inspectorSelection) { _, newValue in
            if newValue != nil { isInspectorPresented = true }
        }
    }

    @ViewBuilder
    private var searchableSidebar: some View {
        if (section ?? .overview).showsSearch {
            DetailSidebar(selection: $section)
                .searchable(text: $searchText, placement: .sidebar, prompt: searchPrompt)
        } else {
            DetailSidebar(selection: $section)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.tccDataSource == .mock || viewModel.btmDataSource == .mock
            || viewModel.launchAgentsDataSource == .mock {
            ToolbarItem(placement: .navigation) { MockBadge() }
        }
        if let onRefresh {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard !isRefreshing else { return }
                    Task { isRefreshing = true; await onRefresh(); isRefreshing = false }
                } label: {
                    Label(String(localized: "Rescan"), systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                .help(String(localized: "Rescan Now"))
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        ToolbarItem(placement: .primaryAction) { ExportToolbarMenu() }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label(String(localized: "Inspector"), systemImage: "sidebar.trailing")
            }
            .help(String(localized: "Show or hide the inspector"))
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    // Hidden buttons give the window ⌘1–⌘6 section switching and ⌘, Preferences
    // access without requiring a menu bar.
    private var windowShortcuts: some View {
        Group {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button("") { section = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }
            Button("") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "preferences")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var detailPage: some View {
        switch section ?? .overview {
        case .overview:
            OverviewPage(section: $section)
        case .permissions: PermissionsDetailPage(searchText: searchText, selection: $inspectorSelection)
        case .launchAgents: LaunchAgentsDetailPage(searchText: searchText, selection: $inspectorSelection)
        case .backgroundItems: BackgroundItemsDetailPage(searchText: searchText, selection: $inspectorSelection)
        case .recentChanges: RecentChangesDetailPage(searchText: searchText)
        case .staleApps: StaleAppsDetailPage(searchText: searchText)
        }
    }

    private var searchPrompt: String {
        switch section ?? .overview {
        case .overview, .permissions: String(localized: "Search permissions")
        case .launchAgents: String(localized: "Search launch agents")
        case .backgroundItems: String(localized: "Search background items")
        case .recentChanges: String(localized: "Search recent changes")
        case .staleApps: String(localized: "Search stale apps")
        }
    }

    private func applyPendingRouteIfAny() {
        guard let route = viewModel.pendingRoute else { return }
        // Suppress the section-change reset only when the section actually
        // changes (onChange won't fire otherwise, so the flag must not stick).
        isApplyingRoute = section != route.sidebarItem
        section = route.sidebarItem
        if let preselect = route.inspectorSelection {
            inspectorSelection = preselect
            isInspectorPresented = true
        }
        viewModel.pendingRoute = nil
    }
}

extension SidebarItem {
    var showsSearch: Bool { self != .overview }
}

// MARK: - Sidebar (native source list)

private struct DetailSidebar: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: SidebarItem?

    var body: some View {
        let changeCount = viewModel.hasUnreviewedChanges ? viewModel.recentChangeEventCount : 0
        let staleCount = viewModel.staleApps.count

        List(selection: $selection) {
            Label(String(localized: "Overview"), systemImage: "gauge.with.needle")
                .tag(SidebarItem.overview)

            Section(String(localized: "Privacy")) {
                Label(String(localized: "Permissions"), systemImage: "lock.shield")
                    .tag(SidebarItem.permissions)
                Label(String(localized: "Launch Agents"), systemImage: "clock")
                    .tag(SidebarItem.launchAgents)
                Label(String(localized: "Background Items"), systemImage: "square.stack.3d.up")
                    .tag(SidebarItem.backgroundItems)
            }

            Section(String(localized: "Activity")) {
                Label(String(localized: "Recent Changes"), systemImage: "clock.arrow.circlepath")
                    .badge(changeCount)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .default, value: changeCount)
                    .tag(SidebarItem.recentChanges)
                Label(String(localized: "Stale Apps"), systemImage: "hourglass")
                    .badge(staleCount)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .default, value: staleCount)
                    .tag(SidebarItem.staleApps)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Permissions page

private struct PermissionsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let searchText: String
    @Binding var selection: InspectorSelection?

    var body: some View {
        VStack(spacing: 0) {
            ScanAvailabilityBanner(
                availability: viewModel.tccAvailability,
                domainName: String(localized: "Permissions")
            )
            .padding([.horizontal, .top], PPSpacing.lg)
            .padding(.bottom, PPSpacing.sm)
            Group {
                if let error = viewModel.tccScanError, isSchemaIssue(error) {
                    VStack(spacing: 0) {
                        SchemaMismatchBanner(error: error, domain: .tcc)
                            .padding(PPSpacing.lg)
                        grantList
                    }
                } else if ScanState.showsScanningPlaceholder(
                    isScanning: viewModel.scanInProgress,
                    isEmpty: viewModel.grants.isEmpty,
                    hasError: viewModel.tccScanError != nil,
                    isSearching: !searchText.isEmpty
                ) {
                    ScanningStateView()
                } else if viewModel.grants.isEmpty {
                    PermissionsEmptyStateView(error: viewModel.tccScanError, domain: .tcc)
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    grantList
                }
            }
        }
        // A scan can land a schema error while the page is open; animate the
        // banner in instead of shoving the list down by a full banner height.
        .animation(reduceMotion ? nil : .default, value: viewModel.tccScanError == nil)
        .navigationTitle(String(localized: "Permissions"))
        .navigationSubtitle(subtitle)
    }

    private var grantList: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                AppGrantRow(group: group)
                    .tag(InspectorSelection.app(appKey: group.appKey))
            }
        }
        .listStyle(.inset)
    }

    private struct AppGrantGroup: Identifiable {
        let appKey: String
        let app: AppIdentity
        let grants: [PermissionGrant]
        var id: String { appKey }
    }

    private var groups: [AppGrantGroup] {
        let filtered: [PermissionGrant]
        if searchText.isEmpty {
            filtered = viewModel.grants
        } else {
            let q = searchText.lowercased()
            filtered = viewModel.grants.filter { grant in
                grant.app.displayName.lowercased().contains(q)
                    || grant.app.bundleID.lowercased().contains(q)
                    || grant.service.displayName.lowercased().contains(q)
            }
        }
        return Dictionary(grouping: filtered, by: \.appKey)
            .map { key, grants in AppGrantGroup(appKey: key, app: grants[0].app, grants: grants) }
            .sorted { $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending }
    }

    private var subtitle: String {
        guard !viewModel.grants.isEmpty else { return "" }
        let appCount = Set(viewModel.grants.map(\.appKey)).count
        let serviceCount = Set(viewModel.grants.map(\.service)).count
        return String(localized: "\(appCount) apps · \(serviceCount) services")
    }

    private struct AppGrantRow: View {
        let group: AppGrantGroup

        var body: some View {
            HStack(spacing: PPSpacing.md) {
                AppIconResolver.iconView(for: group.app, size: 28)
                VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                    Text(group.app.displayName).ppFont(.body)
                    Text(serviceLine)
                        .ppFont(.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PPSpacing.sm)
                Text("\(distinctServices.count)")
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, PPSpacing.xxs)
            .accessibilityElement(children: .combine)
        }

        private var distinctServices: [String] {
            Set(group.grants.map(\.service))
                .map(\.displayName)
                .sorted()
        }

        private var serviceLine: String {
            distinctServices.joined(separator: " · ")
        }
    }
}

// MARK: - Launch Agents page

private struct LaunchAgentsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    let searchText: String
    @Binding var selection: InspectorSelection?

    var body: some View {
        VStack(spacing: 0) {
            ScanAvailabilityBanner(
                availability: viewModel.launchAgentAvailability,
                domainName: String(localized: "Launch Agents")
            )
            .padding([.horizontal, .top], PPSpacing.lg)
            .padding(.bottom, PPSpacing.sm)
            Group {
                if let error = viewModel.launchAgentScanError, viewModel.launchAgents.isEmpty {
                    errorView(error: error)
                } else if ScanState.showsScanningPlaceholder(
                    isScanning: viewModel.scanInProgress,
                    isEmpty: viewModel.launchAgents.isEmpty,
                    hasError: viewModel.launchAgentScanError != nil,
                    isSearching: !searchText.isEmpty
                ) {
                    ScanningStateView()
                } else if viewModel.launchAgents.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Launch Agents"),
                        systemImage: "gearshape.2",
                        description: Text(String(localized: "No launch agents or daemons were found on this system."))
                    )
                } else if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    agentList
                }
            }
        }
        .navigationTitle(String(localized: "Launch Agents"))
        .navigationSubtitle(subtitle)
    }

    private var agentList: some View {
        List(selection: $selection) {
            ForEach(filteredItems) { item in
                LaunchAgentRow(item: item)
                    .tag(InspectorSelection.launchAgent(id: item.id))
            }
        }
        .listStyle(.inset)
    }

    private func errorView(error: ScannerError) -> some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, PPSpacing.xxl)
    }

    private var filteredItems: [LaunchAgentItem] {
        if searchText.isEmpty { return viewModel.launchAgents }
        let q = searchText.lowercased()
        return viewModel.launchAgents.filter { item in
            item.label.lowercased().contains(q)
                || (item.programPath?.lowercased().contains(q) ?? false)
        }
    }

    private var subtitle: String {
        guard !viewModel.launchAgents.isEmpty else { return "" }
        return String(localized: "\(viewModel.launchAgents.count) agents across user and system scopes")
    }
}

private struct LaunchAgentRow: View {
    let item: LaunchAgentItem

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            Image(systemName: "gearshape.2")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(item.label).ppFont(.body).lineLimit(1)
                Text(item.sourceDirectory.path)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, PPSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Background Items page

private struct BackgroundItemsDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let searchText: String
    @Binding var selection: InspectorSelection?

    var body: some View {
        VStack(spacing: 0) {
            ScanAvailabilityBanner(
                availability: viewModel.btmAvailability,
                domainName: String(localized: "Background Items")
            )
            .padding([.horizontal, .top], PPSpacing.lg)
            .padding(.bottom, PPSpacing.sm)
            Group {
                if let error = viewModel.btmScanError, isSchemaIssue(error) {
                    VStack(spacing: 0) {
                        SchemaMismatchBanner(error: error, domain: .btm)
                            .padding(PPSpacing.lg)
                        btmList
                    }
                } else if ScanState.showsScanningPlaceholder(
                    isScanning: viewModel.scanInProgress,
                    isEmpty: viewModel.btmItems.isEmpty,
                    hasError: viewModel.btmScanError != nil,
                    isSearching: !searchText.isEmpty
                ) {
                    ScanningStateView()
                } else if viewModel.btmItems.isEmpty {
                    PermissionsEmptyStateView(error: viewModel.btmScanError, domain: .btm)
                } else if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    btmList
                }
            }
        }
        // Same banner-insertion animation as the Permissions page.
        .animation(reduceMotion ? nil : .default, value: viewModel.btmScanError == nil)
        .navigationTitle(String(localized: "Background Items"))
        .navigationSubtitle(subtitle)
    }

    private var btmList: some View {
        List(selection: $selection) {
            ForEach(filteredItems) { item in
                BTMListRow(item: item)
                    .tag(InspectorSelection.backgroundItem(id: item.id))
            }
        }
        .listStyle(.inset)
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

    private var subtitle: String {
        guard !viewModel.btmItems.isEmpty else { return "" }
        let enabled = viewModel.btmItems.filter { $0.disposition == .enabled }.count
        return String(localized: "\(viewModel.btmItems.count) items · \(enabled) enabled")
    }
}

private struct BTMListRow: View {
    let item: BTMItem

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            iconView
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(item.name).ppFont(.body).lineLimit(1)
                Text(secondaryLine)
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: PPSpacing.sm)
            DispositionBadge(disposition: item.disposition)
        }
        .padding(.vertical, PPSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        if let bid = item.bundleIdentifier, !bid.isEmpty {
            AppIconResolver.iconView(
                for: AppIdentity(bundleID: bid, displayName: item.name, bundlePath: nil),
                size: 28
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: item.type.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var secondaryLine: String {
        let parts: [String] = [
            item.developerName ?? item.bundleIdentifier ?? item.identifier,
            item.scope.displayName,
            item.type.displayName,
        ]
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recent Changes page

private struct RecentChangesDetailPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var window: RecentWindow = .yesterday
    let searchText: String

    var body: some View {
        // The diff content (a List or ContentUnavailableView) is the detail-pane
        // root, matching every other section. A bare VStack root here let the
        // pane size to its content instead of filling, which made
        // NavigationSplitView mis-lay-out its sidebar column. The window picker
        // rides in a top safe-area inset — pinned without distorting the pane,
        // and it also keeps the picker steady across populated/empty windows.
        diffContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("", selection: $window) {
                    Text(String(localized: "Yesterday")).tag(RecentWindow.yesterday)
                    Text(String(localized: "Last 7 days")).tag(RecentWindow.week)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(String(localized: "Change window"))
                .padding(PPSpacing.lg)
                .background(.windowBackground)
            }
            .navigationTitle(String(localized: "Recent Changes"))
    }

    @ViewBuilder
    private var diffContent: some View {
        switch window {
        case .yesterday:
            DiffTabView(
                diff: viewModel.latestDiffYesterday,
                windowLabel: .yesterday,
                searchText: searchText,
                snapshotStoreUnavailable: viewModel.snapshotStoreUnavailable,
                diffUnavailable: viewModel.diffUnavailable
            )
        case .week:
            DiffTabView(
                diff: viewModel.latestDiffWeek,
                windowLabel: .lastWeek,
                searchText: searchText,
                snapshotStoreUnavailable: viewModel.snapshotStoreUnavailable,
                diffUnavailable: viewModel.diffUnavailable
            )
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
        Group {
            if filteredApps.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                StaleAppsTabView(staleApps: filteredApps, staleThresholdDays: viewModel.staleThresholdDays)
            }
        }
        .navigationTitle(String(localized: "Stale Apps"))
        .navigationSubtitle(subtitle)
    }

    private var filteredApps: [StaleApp] {
        if searchText.isEmpty { return viewModel.staleApps }
        let q = searchText.lowercased()
        return viewModel.staleApps.filter { app in
            app.app.displayName.lowercased().contains(q)
                || app.app.bundleID.lowercased().contains(q)
        }
    }

    private var subtitle: String {
        if viewModel.staleApps.isEmpty { return "" }
        return String(localized: "Apps with active grants you haven't used in \(viewModel.staleThresholdDays)+ days")
    }
}

// MARK: - Helpers

// Shared by the three inventory pages while the initial scan is running.
private struct ScanningStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text(String(localized: "Scanning…"))
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
        } description: {
            Text(String(localized: "Reading the system's records. This takes a moment."))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Scanning in progress"))
    }
}

private func isSchemaIssue(_ error: ScannerError) -> Bool {
    switch error {
    case .schemaMismatch, .unsupportedOnThisOS: true
    default: false
    }
}
