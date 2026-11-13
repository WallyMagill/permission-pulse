import AppKit // AppKit: NSApp.activate before openWindow so the Preferences window actually fronts.
import SwiftUI
import PermissionsCore
import PermissionsStore

public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    private let onRefresh: (() async -> Void)?
    private let onRecentChangesReviewed: (() -> Void)?
    private let onBecameVisible: (() -> Void)?

    @State private var section: SidebarItem? = .overview
    @State private var inspectorSelection: InspectorSelection?
    @State private var isInspectorPresented = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var isApplyingRoute = false
    /// A routed search waiting for the section change that would clear it.
    @State private var routeSearchText: String?

    /// `onRecentChangesReviewed` runs when the user leaves Recent Changes
    /// (another section or closing the window) or chooses Mark All Reviewed.
    public init(
        onRefresh: (() async -> Void)? = nil,
        onRecentChangesReviewed: (() -> Void)? = nil,
        onBecameVisible: (() -> Void)? = nil
    ) {
        self.onRefresh = onRefresh
        self.onRecentChangesReviewed = onRecentChangesReviewed
        self.onBecameVisible = onBecameVisible
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
        .onAppear {
            applyPendingRouteIfAny()
            viewModel.isViewingRecentChanges = section == .recentChanges
            onBecameVisible?()
        }
        .onDisappear {
            guard section == .recentChanges else { return }
            onRecentChangesReviewed?()
            viewModel.isViewingRecentChanges = false
        }
        .onChange(of: viewModel.pendingRoute) { _, _ in applyPendingRouteIfAny() }
        .onChange(of: section) { oldSection, newSection in
            handleSectionChange(from: oldSection, to: newSection)
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
        case .recentChanges:
            RecentChangesDetailPage(searchText: searchText, onMarkAllReviewed: onRecentChangesReviewed)
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

    private func handleSectionChange(from oldSection: SidebarItem?, to newSection: SidebarItem?) {
        // Rows stay on screen for the whole visit; leaving marks them
        // reviewed so the next visit starts clean.
        if oldSection == .recentChanges, newSection != .recentChanges {
            onRecentChangesReviewed?()
        }
        viewModel.isViewingRecentChanges = newSection == .recentChanges
        // Reset per-context state: the search field and any inspector
        // selection would otherwise dangle into a section that can't show them.
        searchText = routeSearchText ?? ""
        routeSearchText = nil
        if isApplyingRoute {
            // Route-driven change: keep the pre-selected inspector item.
            isApplyingRoute = false
        } else {
            inspectorSelection = nil
        }
    }

    private func applyPendingRouteIfAny() {
        guard let route = viewModel.pendingRoute else { return }
        // Suppress the section-change reset only when the section actually
        // changes (onChange won't fire otherwise, so the flag must not stick).
        isApplyingRoute = section != route.sidebarItem
        if isApplyingRoute {
            routeSearchText = route.searchText
        } else if let text = route.searchText {
            searchText = text
        }
        if route == .recentChanges { viewModel.recentChangesWindow = .sinceLastReview }
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
        let changeCount = viewModel.unreviewedChangeCount
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
                    // VoiceOver otherwise announces the badge as a bare number.
                    .accessibilityLabel(recentChangesA11yLabel(changeCount))
                Label(String(localized: "Stale Apps"), systemImage: "hourglass")
                    .badge(staleCount)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .default, value: staleCount)
                    .tag(SidebarItem.staleApps)
                    .accessibilityLabel(staleAppsA11yLabel(staleCount))
            }
        }
        .listStyle(.sidebar)
    }

    private func recentChangesA11yLabel(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Recent Changes")
        case 1: String(localized: "Recent Changes, 1 unreviewed change")
        default: String(localized: "Recent Changes, \(count) unreviewed changes")
        }
    }

    private func staleAppsA11yLabel(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Stale Apps")
        case 1: String(localized: "Stale Apps, 1 stale app")
        default: String(localized: "Stale Apps, \(count) stale apps")
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
        // Same ContentUnavailableView treatment as the Permissions and
        // Background Items error states, for cross-page consistency.
        ContentUnavailableView {
            Label(String(localized: "Couldn't read Launch Agents"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? String(localized: "An error occurred reading the LaunchAgents directories."))
        }
    }

    private var filteredItems: [LaunchAgentItem] {
        LaunchAgentDisplay.filtered(viewModel.launchAgents, searchText: searchText)
    }

    private var subtitle: String {
        guard !viewModel.launchAgents.isEmpty else { return "" }
        let count = viewModel.launchAgents.count
        return count == 1
            ? String(localized: "1 agent across user and system scopes")
            : String(localized: "\(count) agents across user and system scopes")
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
        let items = viewModel.btmItems.count == 1
            ? String(localized: "1 item")
            : String(localized: "\(viewModel.btmItems.count) items")
        return String(localized: "\(items) · \(enabled) enabled")
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
                RoundedRectangle(cornerRadius: PPRadius.small, style: .continuous)
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

// MARK: - Helpers

// Shared by the three inventory pages while the initial scan is running.
struct ScanningStateView: View {
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

func isSchemaIssue(_ error: ScannerError) -> Bool {
    switch error {
    case .schemaMismatch, .unsupportedOnThisOS: true
    default: false
    }
}
