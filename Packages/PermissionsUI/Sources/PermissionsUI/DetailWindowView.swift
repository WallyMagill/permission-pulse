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
        @Bindable var bindableViewModel = viewModel

        NavigationSplitView {
            DetailSidebar(selection: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .searchable(text: $searchText, placement: .sidebar, prompt: searchPrompt)
        } detail: {
            detailPage
                .navigationTitle(String(localized: "Permission Pulse"))
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorPanel(selection: inspectorSelection)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(windowShortcuts)
        // KEPT until Task 9: the menu-bar FDA prompt routes through this sheet.
        .sheet(isPresented: $bindableViewModel.showFDASheetOnDetail) {
            FDAGrantSheet()
        }
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
            // Placeholder until Task 6 lands OverviewPage.
            ContentUnavailableView(
                String(localized: "Overview"),
                systemImage: "gauge.with.needle",
                description: Text(String(localized: "Coming in Task 6"))
            )
        case .permissions: PermissionsDetailPage(searchText: searchText, selection: $inspectorSelection)
        case .launchAgents: LaunchAgentsDetailPage(searchText: searchText)
        case .backgroundItems: BackgroundItemsDetailPage(searchText: searchText)
        case .recentChanges: RecentChangesDetailPage()
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

// MARK: - Sidebar (native source list)

private struct DetailSidebar: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var selection: SidebarItem?

    var body: some View {
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
                    .badge(viewModel.hasUnreviewedChanges ? viewModel.recentChangeEventCount : 0)
                    .tag(SidebarItem.recentChanges)
                Label(String(localized: "Stale Apps"), systemImage: "hourglass")
                    .badge(viewModel.staleApps.count)
                    .tag(SidebarItem.staleApps)
            }
        }
        .listStyle(.sidebar)
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
    @Binding var selection: InspectorSelection?

    var body: some View {
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
                ScanningPlaceholder()
            } else if viewModel.grants.isEmpty {
                PermissionsEmptyStateView(error: viewModel.tccScanError, domain: .tcc)
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                grantList
            }
        }
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
