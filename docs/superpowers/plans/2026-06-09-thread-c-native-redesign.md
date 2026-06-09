# Thread C — Pure-Native Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure every Permission Pulse surface into a pure system-native macOS app: glance+handoff dropdown with deep links, NavigationSplitView window with grouped sidebar + Overview landing, non-modal trailing inspector replacing all item sheets, native Settings tabs, and native onboarding.

**Architecture:** A new route model (`AppRoute`) carries deep links from the dropdown into the detail window; an `InspectorSelection` + pure resolver maps list selection to inspector content. Views are rebuilt on native components (`List(selection:)`, `.inspector`, `ContentUnavailableView`, `TabView`, grouped `Form`) while keeping all Thread B design tokens and every Thread A behavior. Scanners/store/models untouched.

**Tech Stack:** SwiftUI (macOS 14+ APIs — package platform is already `.macOS(.v14)`), Swift Testing, existing local SwiftPM packages. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-09-thread-c-native-redesign-design.md`

## Approved deviations from spec (data-honesty + simplification)

1. **Media row copy is device-level** — "Microphone is in use", not "Zoom is using the mic". CMIO `DeviceIsRunningSomewhere` does not identify the app; never invent attribution.
2. **Changes are grouped by domain within the Yesterday / Last 7 days windows** (existing data shape), not per-day — we only store daily snapshots and two diff windows.
3. **`FDAGrantSheet` is deleted, not restyled** — the FDA walkthrough already lives in the full-page `PermissionsEmptyStateView` (grant button, relaunch hint, "why" disclosure) and in the Welcome FDA step. One surface, no extra modal.
4. **Dropdown loses the "What Changed ⌘W" footer button** — the changes status row replaces it.

## Build & test commands

```bash
# Package tests (run from repo root)
cd Packages/PermissionsUI && swift test          # UI package (the one this plan edits)
cd Packages/PermissionsCore && swift test        # only if you touch nothing here, skip
# App target build (from repo root)
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse build
```

If the scheme name differs, list with `xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -list`.

## File structure (end state)

```
Packages/PermissionsUI/Sources/PermissionsUI/
├── Navigation/
│   ├── AppRoute.swift                 (NEW — SidebarItem + AppRoute + route application)
│   └── InspectorSelection.swift       (NEW — InspectorSelection + InspectorContent + resolver)
├── Inspectors/
│   ├── InspectorPanel.swift           (NEW — shared scaffold, switches on resolved content)
│   ├── AppPermissionsInspector.swift  (NEW — ported from AppPermissionsDetailSheet)
│   ├── LaunchAgentInspector.swift     (NEW — ported from LaunchAgentDetailSheet)
│   └── BackgroundItemInspector.swift  (NEW — ported from BackgroundItemDetailSheet)
├── AttentionState.swift               (NEW — extracted from MenuBarContentView, testable)
├── DropdownStatus.swift               (NEW — dropdown status-row builder, testable)
├── DispositionBadge.swift             (NEW — consolidated from BTM sheet/section)
├── OverviewPage.swift                 (NEW — window landing page)
├── DetailWindowView.swift             (REWRITTEN — native sidebar, inspector, pages)
├── MenuBarContentView.swift           (REWRITTEN — glance + handoff)
├── PreferencesWindowView.swift        (REWRITTEN — TabView, 4 tabs)
├── WelcomeWindowView.swift            (REWRITTEN — two-step onboarding)
├── AppViewModel.swift                 (MODIFIED — pendingRoute, lastScanDate, counts)
├── PreferencesViewModel.swift         (MODIFIED — launch-at-login)
├── DiffTabView.swift                  (MODIFIED — native List restyle)
├── StaleAppsTabView.swift             (MODIFIED — native List restyle)
├── PermissionsEmptyStateView.swift    (MODIFIED — ContentUnavailableView where it fits)
├── DetailSheetStyle.swift             (MODIFIED — sheet-only pieces removed; KV/pill/flow kept for inspectors)
└── DELETED: AppPermissionsDetailSheet.swift, LaunchAgentDetailSheet.swift,
            BackgroundItemDetailSheet.swift, FDAGrantSheet.swift,
            ResetConfirmationSheet.swift, PermissionsSection.swift,
            LaunchAgentsSection.swift, BackgroundItemsSection.swift,
            TappableRow.swift, ScanningPlaceholder.swift

PermissionPulse/PermissionPulse/
└── PermissionPulseApp.swift           (MODIFIED — reset flow simplified, launch-at-login, lastScanDate)

Packages/PermissionsUI/Tests/PermissionsUITests/
├── AppRouteTests.swift                (NEW)
├── InspectorContentResolverTests.swift(NEW)
├── AttentionStateTests.swift          (NEW)
├── DropdownStatusTests.swift          (NEW)
└── PreferencesViewModelTests.swift    (MODIFIED — launch-at-login cases)
```

Conventions for every task: all user-facing strings via `String(localized:)`; tokens (`PPSpacing`/`PPFont`/`PPColor`/`PPRadius`) for any custom styling; extract subviews before a `body` passes 60 lines; files ≤ 400 lines preferred.

---

### Task 1: Route model + AppViewModel routing (TDD)

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/Navigation/AppRoute.swift`
- Create: `Packages/PermissionsUI/Tests/PermissionsUITests/AppRouteTests.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift:336,346` (mechanical call-site swap)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift:59-71,100-107` (mechanical call-site swap)

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/PermissionsUI/Tests/PermissionsUITests/AppRouteTests.swift
import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite("AppRoute")
struct AppRouteTests {
    @Test("Every route maps to its sidebar section")
    func routeSidebarMapping() {
        #expect(AppRoute.overview.sidebarItem == .overview)
        #expect(AppRoute.permissions(selectAppKey: nil).sidebarItem == .permissions)
        #expect(AppRoute.permissions(selectAppKey: "com.zoom.xos").sidebarItem == .permissions)
        #expect(AppRoute.launchAgents(selectID: nil).sidebarItem == .launchAgents)
        #expect(AppRoute.backgroundItems(selectID: nil).sidebarItem == .backgroundItems)
        #expect(AppRoute.recentChanges.sidebarItem == .recentChanges)
        #expect(AppRoute.staleApps.sidebarItem == .staleApps)
    }
}

@Suite("AppViewModel routing")
@MainActor
struct AppViewModelRoutingTests {
    private func grant(_ bundleID: String, _ service: PermissionService) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 2
        )
    }

    private func diffs(addedGrants: [PermissionGrant], from: Int64 = 41, to: Int64 = 42) -> SnapshotDiffs {
        SnapshotDiffs(
            fromID: SnapshotID(rawValue: from),
            toID: SnapshotID(rawValue: to),
            tcc: TCCGrantsDiff(added: addedGrants, removed: [], changed: []),
            btm: BTMItemsDiff(added: [], removed: [], changed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [], changed: [])
        )
    }

    @Test("recentChangeEventCount uses yesterday diff when it has content")
    func countPrefersYesterday() {
        let vm = AppViewModel(
            latestDiffYesterday: diffs(addedGrants: [grant("a", .camera), grant("b", .microphone)]),
            latestDiffWeek: diffs(addedGrants: [grant("c", .camera)])
        )
        #expect(vm.recentChangeEventCount == 2)
    }

    @Test("recentChangeEventCount falls back to week diff when yesterday is empty")
    func countFallsBackToWeek() {
        let vm = AppViewModel(
            latestDiffYesterday: diffs(addedGrants: []),
            latestDiffWeek: diffs(addedGrants: [grant("c", .camera)])
        )
        #expect(vm.recentChangeEventCount == 1)
    }

    @Test("recentChangeEventCount is zero with no diffs")
    func countZeroWithNoDiffs() {
        #expect(AppViewModel().recentChangeEventCount == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/PermissionsUI && swift test --filter AppRoute`
Expected: FAIL — `AppRoute` and `recentChangeEventCount` not defined.

- [ ] **Step 3: Create the route model**

```swift
// Packages/PermissionsUI/Sources/PermissionsUI/Navigation/AppRoute.swift
import Foundation

/// Sidebar destinations in the detail window, in display order.
public enum SidebarItem: Hashable, Sendable, CaseIterable {
    case overview
    case permissions
    case launchAgents
    case backgroundItems
    case recentChanges
    case staleApps
}

/// A deep-link destination. Glance surfaces (the dropdown) emit routes; the
/// detail window consumes them: select the sidebar section and, when a route
/// carries an item identifier, pre-select that item so the inspector opens.
public enum AppRoute: Hashable, Sendable {
    case overview
    case permissions(selectAppKey: String?)
    case launchAgents(selectID: String?)
    case backgroundItems(selectID: String?)
    case recentChanges
    case staleApps

    public var sidebarItem: SidebarItem {
        switch self {
        case .overview: .overview
        case .permissions: .permissions
        case .launchAgents: .launchAgents
        case .backgroundItems: .backgroundItems
        case .recentChanges: .recentChanges
        case .staleApps: .staleApps
        }
    }
}
```

- [ ] **Step 4: Modify AppViewModel**

In `AppViewModel.swift`:
1. Delete the `DetailMode` enum (lines 18–21), the `pendingDetailMode` property (line 47 + its comment), the `pendingDetailMode` init parameter (line 84) and assignment (line 105).
2. Add, where `pendingDetailMode` was:

```swift
    // Set by glance surfaces (dropdown rows) before opening the detail
    // window. The window consumes it on appear / onChange, then clears it.
    public var pendingRoute: AppRoute?

    // Stamped by AppDelegate after each completed scan; Overview displays it.
    public var lastScanDate: Date?
```

3. Add below `hasUnreviewedChanges`:

```swift
    /// The diff window glance surfaces summarize: yesterday when it has
    /// content, otherwise the 7-day fallback. (Single source of truth — the
    /// dropdown and sidebar previously each re-derived this.)
    public var activeDiff: SnapshotDiffs? {
        if let primary = latestDiffYesterday, primary.hasContent { return primary }
        return latestDiffWeek
    }

    public var recentChangeEventCount: Int {
        guard let diff = activeDiff else { return 0 }
        return diff.tcc.added.count + diff.tcc.removed.count
            + diff.btm.added.count + diff.btm.removed.count
            + diff.launchAgents.added.count + diff.launchAgents.removed.count
    }
```

- [ ] **Step 5: Mechanical call-site swaps (keep the build green)**

In `MenuBarContentView.swift`: line 336 `viewModel.pendingDetailMode = .whatChanged` → `viewModel.pendingRoute = .recentChanges`; line 346 `viewModel.pendingDetailMode = .current` → `viewModel.pendingRoute = .permissions(selectAppKey: nil)`.

In `DetailWindowView.swift`, replace `applyPendingModeIfAny()` (lines 100–107) with:

```swift
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
```

and update lines 59–60 to call it / observe `viewModel.pendingRoute`. (Overview temporarily lands on Permissions; Task 3 replaces this whole view.) Also replace the duplicated `recentEventCount` computation in `DetailSidebar` (lines 198–209) with `viewModel.recentChangeEventCount`.

- [ ] **Step 6: Run tests, build app**

Run: `cd Packages/PermissionsUI && swift test`
Expected: PASS (all, including new AppRoute suites).
Run: `xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(ui): AppRoute deep-link model + viewModel routing state (Thread C T1)"
```

---

### Task 2: InspectorSelection + content resolver (TDD)

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/Navigation/InspectorSelection.swift`
- Create: `Packages/PermissionsUI/Tests/PermissionsUITests/InspectorContentResolverTests.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/Navigation/AppRoute.swift` (add `inspectorSelection`)

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/PermissionsUI/Tests/PermissionsUITests/InspectorContentResolverTests.swift
import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("InspectorContentResolver")
struct InspectorContentResolverTests {
    private func grant(_ bundleID: String, _ service: PermissionService) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 2
        )
    }

    private var agent: LaunchAgentItem {
        LaunchAgentItem(
            label: "com.test.agent", sourceDirectory: .userLaunchAgents,
            programPath: "/usr/bin/true", programArguments: [],
            runAtLoad: true, keepAlive: false, isDisabled: false
        )
    }

    private var btm: BTMItem {
        BTMItem(
            identifier: "btm-1", name: "Test Item", developerName: nil,
            bundleIdentifier: "com.test.item", teamIdentifier: nil,
            type: .app, disposition: .enabled, dispositionRaw: 2,
            scope: .user, modificationDate: Date(timeIntervalSince1970: 0),
            parentIdentifier: nil
        )
    }

    @Test("Resolves an app selection to its full grant group")
    func resolvesAppGroup() {
        let grants = [grant("com.a", .camera), grant("com.a", .microphone), grant("com.b", .camera)]
        let content = InspectorContentResolver.resolve(
            .app(appKey: "com.a"), grants: grants, launchAgents: [], btmItems: []
        )
        guard case .app(let app, let appGrants) = content else {
            Issue.record("Expected .app content"); return
        }
        #expect(app.bundleID == "com.a")
        #expect(appGrants.count == 2)
    }

    @Test("Resolves launch agent and background item by ID")
    func resolvesByID() {
        let la = InspectorContentResolver.resolve(
            .launchAgent(id: agent.id), grants: [], launchAgents: [agent], btmItems: []
        )
        #expect(la == .launchAgent(agent))
        let bg = InspectorContentResolver.resolve(
            .backgroundItem(id: "btm-1"), grants: [], launchAgents: [], btmItems: [btm]
        )
        #expect(bg == .backgroundItem(btm))
    }

    @Test("Returns nil for nil selection or items no longer present")
    func unresolvable() {
        #expect(InspectorContentResolver.resolve(nil, grants: [], launchAgents: [], btmItems: []) == nil)
        #expect(InspectorContentResolver.resolve(
            .app(appKey: "gone"), grants: [], launchAgents: [], btmItems: []
        ) == nil)
        #expect(InspectorContentResolver.resolve(
            .launchAgent(id: "gone"), grants: [], launchAgents: [agent], btmItems: []
        ) == nil)
    }

    @Test("Routes carry their pre-selection")
    func routeSelectionPayload() {
        #expect(AppRoute.permissions(selectAppKey: "com.a").inspectorSelection == .app(appKey: "com.a"))
        #expect(AppRoute.permissions(selectAppKey: nil).inspectorSelection == nil)
        #expect(AppRoute.launchAgents(selectID: "x").inspectorSelection == .launchAgent(id: "x"))
        #expect(AppRoute.backgroundItems(selectID: "y").inspectorSelection == .backgroundItem(id: "y"))
        #expect(AppRoute.recentChanges.inspectorSelection == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/PermissionsUI && swift test --filter InspectorContentResolver`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement**

```swift
// Packages/PermissionsUI/Sources/PermissionsUI/Navigation/InspectorSelection.swift
import Foundation
import PermissionsCore

/// What the user has selected in a section list. Drives the trailing
/// inspector. Identifier-based so selection survives data refreshes.
public enum InspectorSelection: Hashable, Sendable {
    case app(appKey: String)            // PermissionGrant.appKey (grouped per app)
    case launchAgent(id: String)        // LaunchAgentItem.id
    case backgroundItem(id: String)     // BTMItem.id
}

/// Resolved inspector content — the data the panel renders.
public enum InspectorContent: Equatable, Sendable {
    case app(AppIdentity, grants: [PermissionGrant])
    case launchAgent(LaunchAgentItem)
    case backgroundItem(BTMItem)
}

/// Pure resolution from a selection to current scan data. Returns nil when
/// the selected item no longer exists (e.g. a change row for a removed app);
/// the panel shows a "no longer present" state for that.
public enum InspectorContentResolver {
    public static func resolve(
        _ selection: InspectorSelection?,
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem]
    ) -> InspectorContent? {
        guard let selection else { return nil }
        switch selection {
        case .app(let appKey):
            let matching = grants.filter { $0.appKey == appKey }
            guard let first = matching.first else { return nil }
            return .app(first.app, grants: matching)
        case .launchAgent(let id):
            guard let item = launchAgents.first(where: { $0.id == id }) else { return nil }
            return .launchAgent(item)
        case .backgroundItem(let id):
            guard let item = btmItems.first(where: { $0.id == id }) else { return nil }
            return .backgroundItem(item)
        }
    }
}
```

Append to `AppRoute` in `AppRoute.swift`:

```swift
    /// The pre-selection carried by this route, if any.
    public var inspectorSelection: InspectorSelection? {
        switch self {
        case .permissions(let key?): .app(appKey: key)
        case .launchAgents(let id?): .launchAgent(id: id)
        case .backgroundItems(let id?): .backgroundItem(id: id)
        default: nil
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/PermissionsUI && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ui): InspectorSelection + pure content resolver (Thread C T2)"
```

---

### Task 3: Window skeleton — native sidebar + inspector scaffold (prototypes spec risk #1)

**Files:**
- Rewrite: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/Inspectors/InspectorPanel.swift`

Existing pages (`PermissionsDetailPage` etc.) keep rendering inside the new shell; their sheets still work until Tasks 4–7 convert them. The page structs and `EmptySearchView`/`isSchemaIssue` helpers from the current file are KEPT verbatim in the rewrite — only the shell (`DetailWindowView`, `DetailSidebar`, `SidebarSection`, `SidebarButton`, `RefreshToolbarButton`, `PreferencesToolbarButton`, `DetailPageScaffold` header usage) changes as below. `DetailPageScaffold` itself stays for now (pages still use it until their own tasks).

- [ ] **Step 1: Rewrite the shell**

Replace `DetailWindowView`, `DetailSidebarSelection`, `DetailSidebar`, `SidebarSection`, `SidebarButton`, `RefreshToolbarButton`, and `PreferencesToolbarButton` with:

```swift
public struct DetailWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    private let onRefresh: (() async -> Void)?
    private let onWhatChangedSelected: (() -> Void)?

    @State private var section: SidebarItem? = .overview
    @State private var inspectorSelection: InspectorSelection?
    @State private var isInspectorPresented = false
    @State private var searchText = ""
    @State private var isRefreshing = false

    public init(
        onRefresh: (() async -> Void)? = nil,
        onWhatChangedSelected: (() -> Void)? = nil
    ) {
        self.onRefresh = onRefresh
        self.onWhatChangedSelected = onWhatChangedSelected
    }

    public var body: some View {
        NavigationSplitView {
            DetailSidebar(selection: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .searchable(text: $searchText, placement: .sidebar, prompt: searchPrompt)
        } detail: {
            detailPage
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorPanel(selection: inspectorSelection)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(sectionShortcuts)
        .onAppear { applyPendingRouteIfAny() }
        .onChange(of: viewModel.pendingRoute) { _, _ in applyPendingRouteIfAny() }
        .onChange(of: section) { _, newSection in
            if newSection == .recentChanges { onWhatChangedSelected?() }
            searchText = ""
            inspectorSelection = nil
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

    // Hidden buttons give the window ⌘1–⌘6 section switching without a menu bar.
    private var sectionShortcuts: some View {
        Group {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button("") { section = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }
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
        case .permissions: PermissionsDetailPage(searchText: searchText)
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
```

Notes for the implementer:
- Delete `RefreshToolbarButton` and `PreferencesToolbarButton` entirely (the gear button is gone — Settings opens from the dropdown ⌘,; the native bordered toolbar buttons replace the custom circles).
- Delete `.navigationTitle(String(localized: "Permission Pulse"))` from the split view root; each page will own `navigationTitle` from Task 4 onward. For this task add `.navigationTitle(String(localized: "Permission Pulse"))` on `detailPage` so the title bar isn't empty.
- Keep the `.sheet(isPresented: $bindableViewModel.showFDASheetOnDetail) { FDAGrantSheet() }` for now (Task 9 removes the flag).
- `if newValue != nil` in `onChange(of: inspectorSelection)` auto-opens the panel on first selection; the toolbar/⌥⌘I toggle can still hide it.

- [ ] **Step 2: Create the inspector scaffold**

```swift
// Packages/PermissionsUI/Sources/PermissionsUI/Inspectors/InspectorPanel.swift
import SwiftUI
import PermissionsCore

/// Trailing inspector content host. Resolves the current selection against
/// live scan data; Tasks 4–5 swap the per-type placeholder for real panels.
struct InspectorPanel: View {
    @Environment(AppViewModel.self) private var viewModel
    let selection: InspectorSelection?

    var body: some View {
        Group {
            switch resolvedContent {
            case .app(let app, _):
                placeholder(title: app.displayName) // Task 4: AppPermissionsInspector
            case .launchAgent(let item):
                placeholder(title: item.label)      // Task 5: LaunchAgentInspector
            case .backgroundItem(let item):
                placeholder(title: item.name)       // Task 5: BackgroundItemInspector
            case nil:
                if selection == nil {
                    ContentUnavailableView(
                        String(localized: "No Selection"),
                        systemImage: "sidebar.trailing",
                        description: Text(String(localized: "Select an item to see its details."))
                    )
                } else {
                    ContentUnavailableView(
                        String(localized: "No Longer Present"),
                        systemImage: "questionmark.app.dashed",
                        description: Text(String(localized: "This item isn't in the latest scan. It may have been removed."))
                    )
                }
            }
        }
    }

    private var resolvedContent: InspectorContent? {
        InspectorContentResolver.resolve(
            selection,
            grants: viewModel.grants,
            launchAgents: viewModel.launchAgents,
            btmItems: viewModel.btmItems
        )
    }

    private func placeholder(title: String) -> some View {
        ContentUnavailableView(title, systemImage: "info.circle")
    }
}
```

- [ ] **Step 3: Build + tests**

Run: `cd Packages/PermissionsUI && swift test` then the xcodebuild command.
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 4: MANUAL GATE — prototype the spec's risk #1 on Tahoe**

Launch the app (`xcodebuild ... build` then open the built product, or run from Xcode). Verify in the detail window:
1. The inspector toggle (toolbar + ⌥⌘I) slides a trailing panel in/out without breaking the `Window(id:)` scene.
2. The sidebar shows grouped sections with native selection; Changes badge appears when there are unreviewed changes.
3. Search field renders in the sidebar; ⌘1–⌘6 switch sections.

**If `.inspector` misbehaves inside this scene on Tahoe** (blank panel, broken toolbar, window resize loop): per spec, fall back to a hand-rolled trailing panel — replace `.inspector(isPresented:)` with an `HStack { detailPage; if isInspectorPresented { Divider(); InspectorPanel(...).frame(width: 300) } }` and an `.animation(.default, value: isInspectorPresented)`. Keep the same state variables so Tasks 4–7 are unaffected. Record which path was taken in the commit message.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ui): native window skeleton — grouped sidebar, inspector scaffold, deep-route consumption (Thread C T3)"
```

---

### Task 4: Permissions page → native List + app inspector

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (PermissionsDetailPage + pass selection binding)
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/Inspectors/AppPermissionsInspector.swift`
- Delete: `Packages/PermissionsUI/Sources/PermissionsUI/AppPermissionsDetailSheet.swift`
- Delete: `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsSection.swift`

- [ ] **Step 1: Rewrite the Permissions page as a selectable native List**

Replace `PermissionsDetailPage` in `DetailWindowView.swift`:

```swift
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
                Text("\(group.grants.count)")
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, PPSpacing.xxs)
            .accessibilityElement(children: .combine)
        }

        private var serviceLine: String {
            Set(group.grants.map(\.service))
                .map(\.displayName)
                .sorted()
                .joined(separator: " · ")
        }
    }
}
```

Update the `detailPage` switch: `case .permissions: PermissionsDetailPage(searchText: searchText, selection: $inspectorSelection)`. Also remove `DetailPageScaffold` usage from this page only (other pages still use it until their tasks).

- [ ] **Step 2: Port the sheet into AppPermissionsInspector**

Create `Inspectors/AppPermissionsInspector.swift`. Port the content of `AppPermissionsDetailSheet.swift` (header, risk panel, service pills, automation card, action footer) with these changes — everything else is a direct move of the existing code:
1. Top-level layout: `ScrollView { VStack(alignment: .leading, spacing: PPSpacing.lg) { ... } .padding(PPSpacing.lg) }` — narrow inspector width, no fixed frame, no Close button (non-modal).
2. Header: icon 40pt, name `.ppFont(.cardHeader)` (2-line limit), bundle ID `.ppFont(.metadata)` selectable.
3. Keep `SheetSectionLabel`, `SheetRiskPanel`, `FlowLayout` + `ServicePillButton`, `SheetKVCard` exactly as the sheet used them.
4. Action footer becomes a vertical group of full-width buttons:

```swift
VStack(spacing: PPSpacing.sm) {
    if let path = app.bundlePath {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([path])
        } label: {
            Label(String(localized: "Reveal in Finder"), systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
    }
    if !resetCommands.isEmpty {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(resetCommands.joined(separator: "\n"), forType: .string)
        } label: {
            Label(String(localized: "Copy Reset Commands"), systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .help(String(localized: "Copies tccutil reset commands to run yourself in Terminal."))
    }
}
.controlSize(.large)
```

(Copy the exact reveal/copy implementations from the sheet's action footer — same behaviors, new layout. Public init: `init(app: AppIdentity, grants: [PermissionGrant])`.)

5. In `InspectorPanel`, replace the `.app` placeholder with `AppPermissionsInspector(app: app, grants: grants)`.

- [ ] **Step 3: Delete the sheet + section**

Delete `AppPermissionsDetailSheet.swift` and `PermissionsSection.swift`. Fix any leftover references (the only consumer was the page rewritten in Step 1; `SectionHeader` may become unused by this — leave it until Task 12's dead-code sweep).

- [ ] **Step 4: Build, test, eyeball**

Run package tests + app build (commands above). Expected: PASS / BUILD SUCCEEDED.
Launch: click an app row → inspector shows its permissions; ↑↓ arrows move selection and the inspector follows; search filters; Reveal/Copy work.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor(ui): Permissions page → native selectable List + AppPermissionsInspector; retire sheet (Thread C T4)"
```

---

### Task 5: Launch Agents + Background Items → native Lists + inspectors

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (both pages + selection bindings)
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/Inspectors/LaunchAgentInspector.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/Inspectors/BackgroundItemInspector.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DispositionBadge.swift` (consolidated)
- Delete: `LaunchAgentDetailSheet.swift`, `BackgroundItemDetailSheet.swift`, `LaunchAgentsSection.swift`, `BackgroundItemsSection.swift`, `TappableRow.swift`

- [ ] **Step 1: Consolidate DispositionBadge**

Move the private `DispositionBadge` (currently duplicated in `BackgroundItemDetailSheet.swift:136-163` and `BackgroundItemsSection.swift`) into its own internal file `DispositionBadge.swift`, unchanged (it already uses contrast-safe `PPBadgeStyle` tokens). Public-ness: `internal`.

- [ ] **Step 2: Rewrite both pages as selectable native Lists**

Same pattern as Task 4's Step 1, applied twice in `DetailWindowView.swift`:

`LaunchAgentsDetailPage(searchText:selection:)` — List rows tagged `InspectorSelection.launchAgent(id: item.id)`; row content: `Image(systemName: "gearshape.2")` in a 28pt frame, label `.ppFont(.body)` (1 line), `item.sourceDirectory.path` `.ppFont(.metadata).foregroundStyle(.secondary)`. Keep the existing error block (the "Couldn't read Launch Agents" VStack) and scanning/empty/search states exactly as the current page has them, but route empty-search through `ContentUnavailableView.search(text:)`. `.navigationTitle(String(localized: "Launch Agents"))`, `.navigationSubtitle` from the current `subtitle` computed property.

`BackgroundItemsDetailPage(searchText:selection:)` — rows tagged `InspectorSelection.backgroundItem(id: item.id)`; row content ported from `BTMItemRow` (icon via synthesized `AppIdentity` when `bundleIdentifier` exists — copy that logic from `BackgroundItemsSection.swift` before deleting it — name, secondary line, trailing `DispositionBadge(disposition: item.disposition)`). Keep the schema banner + scanning/empty states pattern from Task 4.

Update the `detailPage` switch to pass `selection: $inspectorSelection` to both.

- [ ] **Step 3: Port the two sheets into inspectors**

`LaunchAgentInspector(item: LaunchAgentItem)` — port from `LaunchAgentDetailSheet.swift`: header (`SheetGradientTile(symbol: "gearshape.fill")` at 40pt, label 2-line, scope line), the `SheetKVCard` property rows (Program, Arguments, Run at load, Keep alive, Disabled), source path card, and a full-width "Reveal in Finder" button (`NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: <plist path>)])` — copy the exact path property the sheet used). Same ScrollView layout conventions as Task 4 Step 2; no Close button.

`BackgroundItemInspector(item: BTMItem)` — port from `BackgroundItemDetailSheet.swift`: header (icon or gradient tile, name, subtitle, `DispositionBadge`), the `SheetKVCard` rows (Type, Scope, Identifier, Bundle ID, Team ID, Modified, Parent), and a full-width "Open Login Items" button calling `SystemSettingsLink.openLoginItems()`.

Wire both into `InspectorPanel` (replace the remaining placeholders; delete the now-unused `placeholder(title:)` helper).

- [ ] **Step 4: Delete retired files**

Delete the five files listed above. `SheetCloseFooter` in `DetailSheetStyle.swift` is now unused — delete that struct (keep `SheetSectionLabel`, `SheetKVRow`, `SheetKVCard`, `SheetRiskPanel`, `SheetGradientTile`, `ServicePillButton`, `FlowLayout`, date helpers — the inspectors use them).

- [ ] **Step 5: Build, test, eyeball, commit**

Package tests + app build: PASS. Launch: agents and background items select → inspector follows; no sheets remain anywhere in the window.

```bash
git add -A && git commit -m "refactor(ui): Launch Agents + Background Items → native Lists + inspectors; retire sheets (Thread C T5)"
```

---

### Task 6: AttentionState extraction (TDD) + Overview landing page

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/AttentionState.swift`
- Create: `Packages/PermissionsUI/Tests/PermissionsUITests/AttentionStateTests.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/OverviewPage.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (swap Overview placeholder)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` (use shared AttentionState)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (stamp `lastScanDate`)

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/PermissionsUI/Tests/PermissionsUITests/AttentionStateTests.swift
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("AttentionState")
struct AttentionStateTests {
    @Test("Clean when no errors")
    func clean() {
        #expect(AttentionState.evaluate(tccError: nil, btmError: nil, launchAgentError: nil) == .clean)
    }

    @Test("TCC permission denial wins over everything")
    func fdaDenied() {
        #expect(AttentionState.evaluate(
            tccError: .permissionDenied, btmError: .permissionDenied, launchAgentError: nil
        ) == .fdaDenied)
    }

    @Test("BTM-only denial is its own state")
    func btmOnly() {
        #expect(AttentionState.evaluate(
            tccError: nil, btmError: .permissionDenied, launchAgentError: nil
        ) == .btmOnlyFDADenied)
    }

    @Test("Schema mismatch and launch-agent errors rank below denial")
    func ordering() {
        #expect(AttentionState.evaluate(
            tccError: .schemaMismatch(details: "x"), btmError: nil, launchAgentError: nil
        ) == .schemaMismatch)
        #expect(AttentionState.evaluate(
            tccError: nil, btmError: nil, launchAgentError: .databaseUnavailable
        ) == .launchAgentError)
    }
}
```

NOTE: `ScannerError` case payloads above are guesses — open `Packages/PermissionsCore/Sources/.../ScannerError.swift` first and use real case spellings (the existing `isPermissionDenied`/`isSchemaIssue` helpers in `MenuBarContentView.swift:301-310` show which cases exist). Same precedence rules as `MenuBarContentView.attentionState` (lines 239-249) — this is an extraction, not new logic.

- [ ] **Step 2: Run to verify failure** — `swift test --filter AttentionState` → FAIL (type missing).

- [ ] **Step 3: Extract the evaluator**

```swift
// Packages/PermissionsUI/Sources/PermissionsUI/AttentionState.swift
import PermissionsCore

/// App-wide "does something need the user's attention" state, shared by the
/// dropdown, Overview page, and menu-bar icon copy. Extracted verbatim from
/// MenuBarContentView's private enum so the precedence is defined once.
public enum AttentionState: Equatable, Sendable {
    case clean
    case fdaDenied
    case btmOnlyFDADenied
    case schemaMismatch
    case launchAgentError

    public static func evaluate(
        tccError: ScannerError?,
        btmError: ScannerError?,
        launchAgentError: ScannerError?
    ) -> AttentionState {
        if isPermissionDenied(tccError) { return .fdaDenied }
        if isPermissionDenied(btmError) { return .btmOnlyFDADenied }
        if isSchemaIssue(tccError) || isSchemaIssue(btmError) { return .schemaMismatch }
        if launchAgentError != nil { return .launchAgentError }
        return .clean
    }

    private static func isPermissionDenied(_ error: ScannerError?) -> Bool {
        if case .permissionDenied = error { true } else { false }
    }

    private static func isSchemaIssue(_ error: ScannerError?) -> Bool {
        switch error {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
        }
    }
}
```

Add a convenience on `AppViewModel`:

```swift
    public var attentionState: AttentionState {
        AttentionState.evaluate(
            tccError: tccScanError,
            btmError: btmScanError,
            launchAgentError: launchAgentScanError
        )
    }
```

In `MenuBarContentView.swift`, delete the private `AttentionState` enum + `attentionState` computed property + the two private helpers, and switch all uses to `viewModel.attentionState` (the case names match). Run `swift test` → PASS.

- [ ] **Step 4: Build the Overview page**

```swift
// Packages/PermissionsUI/Sources/PermissionsUI/OverviewPage.swift
import SwiftUI
import PermissionsCore

/// The window's landing page: answers "am I okay?" — every row deep-links.
struct OverviewPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var section: SidebarItem?

    var body: some View {
        Form {
            if hasAttentionContent {
                Section(String(localized: "Needs Attention")) {
                    attentionRows
                }
            }
            Section(String(localized: "At a Glance")) {
                countRow(
                    title: String(localized: "Permissions"),
                    systemImage: "lock.shield",
                    count: viewModel.grants.count,
                    target: .permissions
                )
                countRow(
                    title: String(localized: "Launch Agents"),
                    systemImage: "clock",
                    count: viewModel.launchAgents.count,
                    target: .launchAgents
                )
                countRow(
                    title: String(localized: "Background Items"),
                    systemImage: "square.stack.3d.up",
                    count: viewModel.btmItems.count,
                    target: .backgroundItems
                )
                if let risk = PermissionRiskSummary.line(for: viewModel.grants) {
                    Label(risk, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.secondary)
                }
            }
            Section(String(localized: "Status")) {
                LabeledContent(String(localized: "Last Scan")) {
                    Text(lastScanText)
                }
                LabeledContent(String(localized: "Full Disk Access")) {
                    Text(fdaStatusText)
                        .foregroundStyle(viewModel.attentionState == .fdaDenied
                            || viewModel.attentionState == .btmOnlyFDADenied
                            ? PPColor.warning : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Overview"))
    }

    private var hasAttentionContent: Bool {
        viewModel.attentionState != .clean || viewModel.hasUnreviewedChanges
    }

    @ViewBuilder
    private var attentionRows: some View {
        switch viewModel.attentionState {
        case .fdaDenied:
            attentionRow(
                String(localized: "Full Disk Access needed to scan permissions"),
                target: .permissions
            )
        case .btmOnlyFDADenied:
            attentionRow(
                String(localized: "Full Disk Access needed for background items"),
                target: .backgroundItems
            )
        case .schemaMismatch:
            attentionRow(
                String(localized: "A data source changed format — some items may be missing"),
                target: .permissions
            )
        case .launchAgentError:
            attentionRow(
                String(localized: "Launch Agents couldn't be read"),
                target: .launchAgents
            )
        case .clean:
            EmptyView()
        }
        if viewModel.hasUnreviewedChanges {
            attentionRow(
                String(localized: "\(viewModel.recentChangeEventCount) unreviewed changes"),
                target: .recentChanges
            )
        }
    }

    private func attentionRow(_ title: String, target: SidebarItem) -> some View {
        Button { section = target } label: {
            HStack {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func countRow(title: String, systemImage: String, count: Int, target: SidebarItem) -> some View {
        Button { section = target } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .ppFont(.badge)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lastScanText: String {
        guard let date = viewModel.lastScanDate else {
            return viewModel.scanInProgress
                ? String(localized: "Scanning…")
                : String(localized: "Not yet scanned")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var fdaStatusText: String {
        switch viewModel.attentionState {
        case .fdaDenied, .btmOnlyFDADenied: String(localized: "Not granted")
        default: String(localized: "Granted")
        }
    }
}
```

(Check `PermissionRiskSummary.line(for:)`'s exact spelling in PermissionsCore before using — `MenuBarContentView.swift:114` is the existing call site.)

In `DetailWindowView.swift`, replace the Overview `ContentUnavailableView` placeholder with `OverviewPage(section: $section)`.

- [ ] **Step 5: Stamp lastScanDate**

In `PermissionPulseApp.swift`, after each `await snapshotCoordinator?.onScanCompleted()` (both in `applicationDidFinishLaunching` and `rescan()`), add `viewModel.lastScanDate = Date()`.

- [ ] **Step 6: Build, test, eyeball, commit**

Package tests + app build: PASS. Launch: Overview lands first, attention/count rows navigate, Status section is honest.

```bash
git add -A && git commit -m "feat(ui): Overview landing page + shared AttentionState evaluator (Thread C T6)"
```

---

### Task 7: Changes + Stale Apps → native restyle

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (RecentChangesDetailPage, StaleAppsDetailPage)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift`

- [ ] **Step 1: Recent Changes page**

In `RecentChangesDetailPage`: drop `DetailPageScaffold`; the segmented Yesterday / Last 7 days `Picker` stays but moves into the toolbar area of the page via `.toolbar { ToolbarItem(placement: .principal) { <picker> } }` — if `.principal` placement renders poorly in this window, keep it as the first element above the list with `PPSpacing.lg` padding. Add `.navigationTitle(String(localized: "Recent Changes"))`. Add a **Mark All Reviewed** affordance: this is the existing `onWhatChangedSelected` behavior which already fires on section entry — so no extra button; instead show a footer note in the list (`Text(String(localized: "Changes are marked reviewed when you visit this page.")).ppFont(.metadata).foregroundStyle(.tertiary)`).

In `DiffTabView.swift`: replace the outer custom stacks/cards with a native `List` containing one `Section` per domain (`Section(String(localized: "Permissions")) { ... }`, Background Items, Launch Agents — only when non-empty, preserving the existing filtering through `DismissedDiffEntryStore.isDismissed`). Keep all empty/error states but render them through `ContentUnavailableView` (e.g. store-unavailable: `ContentUnavailableView(String(localized: "History Unavailable"), systemImage: "externaldrive.badge.exclamationmark", description: Text(<existing copy>))`). Keep the dismissed-row confirmation alert exactly as is.

In `ChangeRow.swift`: keep the row content (colored +/− indicator, summary text) but replace the trailing ⋯ `Menu` with a native `.contextMenu` on the row containing the same two actions ("Snooze 7 days", "Dismiss forever" with `role: .destructive`). Keep the `onDismissForever`/`onSnooze` callback signatures unchanged. Add `.help(String(localized: "Right-click for dismiss options"))`.

- [ ] **Step 2: Stale Apps page**

In `StaleAppsDetailPage`: drop `DetailPageScaffold`, add `.navigationTitle(String(localized: "Stale Apps"))` + `.navigationSubtitle` (the existing threshold copy). In `StaleAppsTabView.swift`: render rows in a native `List`; move "Reveal in Finder" + "Skip forever" from the ⋯ menu to a `.contextMenu` (keep the skip-forever confirmation alert + `DismissedStaleAppStore` wiring unchanged); empty state → `ContentUnavailableView(String(localized: "No Stale Apps"), systemImage: "checkmark.circle", description: Text(<existing copy>))`. Row keeps icon 28pt, name, bundle ID, last-used line (`.ppFont(.metadata)`).

- [ ] **Step 3: Build, test, eyeball, commit**

Package tests + app build: PASS. Launch: changes render in native sections, context menus dismiss/snooze, stale rows context-menu works, badge clears on visiting Changes.

```bash
git add -A && git commit -m "refactor(ui): Changes + Stale Apps pages → native Lists with context menus (Thread C T7)"
```

---

### Task 8: Empty & edge states → ContentUnavailableView

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (delete `EmptySearchView`)
- Delete: `Packages/PermissionsUI/Sources/PermissionsUI/ScanningPlaceholder.swift`

- [ ] **Step 1: Scanning state**

Find all `ScanningPlaceholder()` uses (Permissions/LaunchAgents/BackgroundItems pages). Replace with:

```swift
ContentUnavailableView {
    Label(String(localized: "Scanning…"), systemImage: "magnifyingglass")
} description: {
    Text(String(localized: "Reading the system's records. This takes a moment."))
}
```

If `ScanningPlaceholder` had a spinner, prepend `ProgressView().controlSize(.small)` inside the label slot instead of the magnifying glass. Then delete `ScanningPlaceholder.swift`. Keep `ScanState.showsScanningPlaceholder` (logic + its tests are untouched).

- [ ] **Step 2: Search + empty states**

Delete the private `EmptySearchView` from `DetailWindowView.swift`; all pages already use `ContentUnavailableView.search(text:)` from Tasks 4–5 — sweep for any remaining `EmptySearchView(` references (Changes/Stale from Task 7) and convert them too.

- [ ] **Step 3: FDA full-page state**

In `PermissionsEmptyStateView.swift`, restyle the permission-denied branch around `ContentUnavailableView`:

```swift
ContentUnavailableView {
    Label(String(localized: "Full Disk Access Required"), systemImage: "lock.shield")
} description: {
    Text(<existing domain-specific body copy>)
} actions: {
    Button(String(localized: "Grant Access in System Settings…")) {
        SystemSettingsLink.openFullDiskAccess()
    }
    .buttonStyle(.borderedProminent)
}
```

Keep (below the ContentUnavailableView, in the same VStack): the relaunch hint + "Quit & Reopen" link and the "Why does Permission Pulse need this?" disclosure — exact existing copy and behaviors. The schema-mismatch / temporarily-unavailable / plain-empty branches also become `ContentUnavailableView`s with their existing copy.

- [ ] **Step 4: Build, test, eyeball, commit**

```bash
git add -A && git commit -m "refactor(ui): native ContentUnavailableView for scanning/empty/search/FDA states (Thread C T8)"
```

---

### Task 9: Dropdown rebuild — glance + handoff (TDD for row derivation)

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DropdownStatus.swift`
- Create: `Packages/PermissionsUI/Tests/PermissionsUITests/DropdownStatusTests.swift`
- Rewrite: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` (delete `showFDASheetOnDetail`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (delete FDA sheet presentation)
- Delete: `Packages/PermissionsUI/Sources/PermissionsUI/FDAGrantSheet.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/PermissionsUI/Tests/PermissionsUITests/DropdownStatusTests.swift
import Testing
@testable import PermissionsUI

@Suite("DropdownStatusBuilder")
struct DropdownStatusTests {
    private func rows(
        attention: AttentionState = .clean,
        mic: Bool = false, camera: Bool = false,
        changeCount: Int = 0, hasUnreviewed: Bool = false,
        staleCount: Int = 0, appCount: Int = 42
    ) -> [DropdownStatusRow] {
        DropdownStatusBuilder.rows(
            attention: attention, micInUse: mic, cameraInUse: camera,
            changeCount: changeCount, hasUnreviewedChanges: hasUnreviewed,
            staleCount: staleCount, appCount: appCount
        )
    }

    @Test("All-clear shows only the summary row, routed to Overview")
    func allClear() {
        let result = rows()
        #expect(result.count == 1)
        #expect(result[0].kind == .allClear(appCount: 42))
        #expect(result[0].route == .overview)
    }

    @Test("Attention row leads and routes to the failing domain")
    func attentionFirst() {
        let result = rows(attention: .fdaDenied, changeCount: 3, hasUnreviewed: true)
        #expect(result.first?.kind == .attention(.fdaDenied))
        #expect(result.first?.route == .permissions(selectAppKey: nil))
        let btm = rows(attention: .btmOnlyFDADenied)
        #expect(btm.first?.route == .backgroundItems(selectID: nil))
        let la = rows(attention: .launchAgentError)
        #expect(la.first?.route == .launchAgents(selectID: nil))
    }

    @Test("Media row appears while mic or camera is in use, routes to Permissions")
    func media() {
        let result = rows(mic: true)
        #expect(result.contains { $0.kind == .media(mic: true, camera: false) })
        #expect(result.first { $0.kind == .media(mic: true, camera: false) }?.route
            == .permissions(selectAppKey: nil))
    }

    @Test("Changes and stale rows appear only with content; order is attention, media, changes, stale, summary")
    func ordering() {
        let result = rows(
            attention: .schemaMismatch, mic: true,
            changeCount: 3, hasUnreviewed: true, staleCount: 5
        )
        #expect(result.map(\.kind) == [
            .attention(.schemaMismatch),
            .media(mic: true, camera: false),
            .changes(count: 3),
            .stale(count: 5),
            .allClear(appCount: 42)
        ])
        #expect(result[2].route == .recentChanges)
        #expect(result[3].route == .staleApps)
    }

    @Test("Reviewed changes don't produce a changes row")
    func reviewedChangesHidden() {
        let result = rows(changeCount: 3, hasUnreviewed: false)
        #expect(!result.contains { if case .changes = $0.kind { true } else { false } })
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter DropdownStatus` → FAIL.

- [ ] **Step 3: Implement the builder**

```swift
// Packages/PermissionsUI/Sources/PermissionsUI/DropdownStatus.swift
import Foundation

/// One glanceable dropdown row: a semantic kind (the view maps it to copy
/// and an SF Symbol) plus the deep-link route a click follows.
public struct DropdownStatusRow: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case attention(AttentionState)
        case media(mic: Bool, camera: Bool)
        case changes(count: Int)
        case stale(count: Int)
        case allClear(appCount: Int)
    }

    public let kind: Kind
    public let route: AppRoute

    public var id: String {
        switch kind {
        case .attention: "attention"
        case .media: "media"
        case .changes: "changes"
        case .stale: "stale"
        case .allClear: "allClear"
        }
    }
}

/// Pure derivation of the dropdown's status rows. Order: attention first,
/// live media, unreviewed changes, stale apps, then the always-present
/// summary row (which doubles as the "all clear" line).
public enum DropdownStatusBuilder {
    public static func rows(
        attention: AttentionState,
        micInUse: Bool,
        cameraInUse: Bool,
        changeCount: Int,
        hasUnreviewedChanges: Bool,
        staleCount: Int,
        appCount: Int
    ) -> [DropdownStatusRow] {
        var result: [DropdownStatusRow] = []
        switch attention {
        case .clean:
            break
        case .fdaDenied, .schemaMismatch:
            result.append(.init(kind: .attention(attention), route: .permissions(selectAppKey: nil)))
        case .btmOnlyFDADenied:
            result.append(.init(kind: .attention(attention), route: .backgroundItems(selectID: nil)))
        case .launchAgentError:
            result.append(.init(kind: .attention(attention), route: .launchAgents(selectID: nil)))
        }
        if micInUse || cameraInUse {
            result.append(.init(
                kind: .media(mic: micInUse, camera: cameraInUse),
                route: .permissions(selectAppKey: nil)
            ))
        }
        if hasUnreviewedChanges && changeCount > 0 {
            result.append(.init(kind: .changes(count: changeCount), route: .recentChanges))
        }
        if staleCount > 0 {
            result.append(.init(kind: .stale(count: staleCount), route: .staleApps))
        }
        result.append(.init(kind: .allClear(appCount: appCount), route: .overview))
        return result
    }
}
```

Run `swift test --filter DropdownStatus` → PASS.

- [ ] **Step 4: Rewrite MenuBarContentView**

Full replacement. KEEP from the old file: `MenuRowButton`, `OptionalShortcut`, `PulseDot`, the `activateAndOpen(_:)` helper. DELETE: `BrandBadge`, `SectionLabel`, `StatRow`, `ActivityRow`, `AttentionBanner`, `RecentEvent`, `recentEvents`, `presentFDASheet`, the private attention helpers (already moved in Task 6).

```swift
public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel
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

    private func activateAndOpen(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

/// One glance row: status icon, copy, trailing chevron. Hover + click like a
/// native menu row; every row is a deep link.
private struct StatusRowButton: View {
    let row: DropdownStatusRow
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .ppFont(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
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
        .accessibilityHint(String(localized: "Opens Permission Pulse"))
    }

    private var title: String {
        switch row.kind {
        case .attention(.fdaDenied):
            String(localized: "Full Disk Access needed")
        case .attention(.btmOnlyFDADenied):
            String(localized: "FDA needed for background items")
        case .attention(.schemaMismatch):
            String(localized: "A data source changed format")
        case .attention(.launchAgentError):
            String(localized: "Launch Agents couldn't be read")
        case .attention(.clean):
            "" // builder never emits this
        case .media(true, true):
            String(localized: "Microphone and camera are in use")
        case .media(true, false):
            String(localized: "Microphone is in use")
        case .media(_, _):
            String(localized: "Camera is in use")
        case .changes(let n):
            String(localized: "\(n) changes since your last review")
        case .stale(let n):
            String(localized: "\(n) stale apps with old permissions")
        case .allClear(let n):
            String(localized: "\(n) apps with permissions")
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
```

- [ ] **Step 5: Retire the FDA sheet**

Delete `showFDASheetOnDetail` from `AppViewModel` (property + init param + assignment), the `.sheet(isPresented: $bindableViewModel.showFDASheetOnDetail)` from `DetailWindowView` (and the now-unneeded `@Bindable` line if unused), and `FDAGrantSheet.swift`. Grep for `showFDASheetOnDetail` and `FDAGrantSheet` — fix every reference (tests included). The FDA path is now: dropdown attention row → Permissions page full-page state → "Grant Access in System Settings…".

- [ ] **Step 6: Build, test, eyeball, commit**

Package tests + app build: PASS. Launch: dropdown shows status rows that each open the window on the right section; footer rows work; mock badge visible in mock runs.

```bash
git add -A && git commit -m "feat(ui): glance+handoff dropdown — status rows deep-link, FDA sheet retired (Thread C T9)"
```

---

### Task 10: Settings → native TabView (General / Scanning / Digest / Data)

**Files:**
- Rewrite: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesViewModel.swift` (launch-at-login)
- Modify: `Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesViewModelTests.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (SMAppService + reset simplification)
- Delete: `Packages/PermissionsUI/Sources/PermissionsUI/ResetConfirmationSheet.swift`

- [ ] **Step 1: Write the failing launch-at-login tests**

Open `PreferencesViewModelTests.swift` to see how the existing callback-injected tests are built (the digest-toggle tests use the same pattern), then add:

```swift
@Test("Launch-at-login toggle applies the system result, not the request")
@MainActor
func launchAtLoginAppliesSystemResult() async {
    var requested: Bool?
    let vm = PreferencesViewModel(
        store: PreferencesStore(defaults: makeTestDefaults()),
        onDigestToggle: { _ in .disabled },
        onSendTestNotification: { .idle },
        onFetchNextFireDate: { nil },
        initialLaunchAtLogin: false,
        onLaunchAtLoginToggle: { enable in
            requested = enable
            return false   // system refused (e.g. SMAppService error)
        }
    )
    await vm.setLaunchAtLogin(true)
    #expect(requested == true)
    #expect(vm.launchAtLoginEnabled == false)  // reflects reality, not the wish
}
```

(Mirror the suite's existing `makeTestDefaults()`/init conventions; add new init params with defaults — `initialLaunchAtLogin: Bool = false`, `onLaunchAtLoginToggle: ((Bool) async -> Bool)? = nil` — so existing tests compile unchanged.)

Run: `swift test --filter PreferencesViewModel` → FAIL.

- [ ] **Step 2: Implement in PreferencesViewModel**

```swift
    public private(set) var launchAtLoginEnabled: Bool
    private let onLaunchAtLoginToggle: ((Bool) async -> Bool)?

    public func setLaunchAtLogin(_ enable: Bool) async {
        guard let onLaunchAtLoginToggle else { return }
        launchAtLoginEnabled = await onLaunchAtLoginToggle(enable)
    }
```

Wire the two new init parameters through. Run the filter → PASS, then full `swift test` → PASS.

- [ ] **Step 3: Rewrite PreferencesWindowView as a native TabView**

Keep the two existing tab content groups (`SnapshotsPreferencesTab` → split into Scanning + Data; `NotificationsPreferencesTab` → Digest) — their controls, validation ranges, and store bindings are reused as-is, just rehosted in grouped `Form`s:

```swift
public struct PreferencesWindowView: View {
    @Environment(PreferencesViewModel.self) private var viewModel
    private let onResetAllData: (() -> Void)?
    private let scanInProgress: () -> Bool

    public init(
        onResetAllData: (() -> Void)? = nil,
        scanInProgress: @escaping () -> Bool = { false }
    ) {
        self.onResetAllData = onResetAllData
        self.scanInProgress = scanInProgress
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            ScanningSettingsTab()
                .tabItem { Label(String(localized: "Scanning"), systemImage: "clock.arrow.circlepath") }
            DigestSettingsTab()
                .tabItem { Label(String(localized: "Digest"), systemImage: "bell.badge") }
            DataSettingsTab(onResetAllData: onResetAllData, scanInProgress: scanInProgress)
                .tabItem { Label(String(localized: "Data"), systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 440)
    }
}
```

- `GeneralSettingsTab`: grouped `Form` with one toggle —

```swift
private struct GeneralSettingsTab: View {
    @Environment(PreferencesViewModel.self) private var viewModel

    var body: some View {
        Form {
            Toggle(
                String(localized: "Launch at login"),
                isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { newValue in Task { await viewModel.setLaunchAtLogin(newValue) } }
                )
            )
            Text(String(localized: "Permission Pulse starts in the menu bar when you log in."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
```

- `ScanningSettingsTab`: grouped `Form` hosting the existing retention-days + stale-threshold controls (move them out of `SnapshotsPreferencesTab` unchanged — same steppers/pickers, same 7…365 / 30…365 ranges, same store bindings).
- `DigestSettingsTab`: grouped `Form` hosting everything from the current `NotificationsPreferencesTab` unchanged (digest toggle + weekday/time pickers + test-notification button + authorization hints).
- `DataSettingsTab`: grouped `Form` with an Export row hosting the existing `ExportToolbarMenu()` (it needs `AppViewModel` — see Step 5) and the reset flow:

```swift
private struct DataSettingsTab: View {
    let onResetAllData: (() -> Void)?
    let scanInProgress: () -> Bool
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Export current state")) {
                    ExportToolbarMenu()
                }
            }
            Section {
                Button(String(localized: "Reset All Data…"), role: .destructive) {
                    isConfirmingReset = true
                }
                .disabled(scanInProgress() || onResetAllData == nil)
                Text(String(localized: "Deletes all snapshots, dismissed items, snoozes, and preferences. This cannot be undone."))
                    .ppFont(.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(String(localized: "Reset Permission Pulse?"), isPresented: $isConfirmingReset) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset"), role: .destructive) { onResetAllData?() }
        } message: {
            Text(String(localized: "All snapshots, dismissed items, snoozes, and preferences will be deleted. This cannot be undone."))
        }
    }
}
```

- [ ] **Step 4: App target — SMAppService + simplified reset**

In `PermissionPulseApp.swift`:
1. `import ServiceManagement`.
2. `requestResetAllData()` body becomes just `Task { @MainActor in await performReset() }` — delete the `ResetConfirmationSheet` window dance and the `resetConfirmationWindow` property (confirmation now lives in the Data tab's alert). Delete `ResetConfirmationSheet.swift`.
3. Extend the `preferencesViewModel` construction:

```swift
        initialLaunchAtLogin: SMAppService.mainApp.status == .enabled,
        onLaunchAtLoginToggle: { enable in
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                Self.logger.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            }
            return SMAppService.mainApp.status == .enabled
        }
```

4. Pass `.environment(appDelegate.viewModel)` to `PreferencesWindowView` in the scene (the Data tab's `ExportToolbarMenu` reads it).

- [ ] **Step 5: Build, test, manual SMAppService check, commit**

Package tests + app build: PASS. MANUAL (per CLAUDE.md fragile-surface rule): toggle Launch at login on a real machine, confirm the app appears/disappears in System Settings → General → Login Items, and that the toggle reflects refusal correctly. Verify reset still wipes and rescans.

```bash
git add -A && git commit -m "feat(ui): native Settings tabs + launch-at-login via SMAppService; native reset confirmation (Thread C T10)"
```

---

### Task 11: Welcome → two-step native onboarding

**Files:**
- Rewrite: `Packages/PermissionsUI/Sources/PermissionsUI/WelcomeWindowView.swift`

- [ ] **Step 1: Rewrite**

```swift
import SwiftUI

public struct WelcomeWindowView: View {
    private let onDismiss: () -> Void
    @State private var step: Step = .features

    private enum Step { case features, fullDiskAccess }

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .features: featuresStep
            case .fullDiskAccess: fdaStep
            }
        }
        .padding(PPSpacing.xl)
        .frame(width: 480, height: 440)
    }

    private var featuresStep: some View {
        VStack(spacing: PPSpacing.lg) {
            Image(systemName: "shield.lefthalf.filled")
                // Decorative hero icon — keep fixed size (rule 1)
                .font(.system(size: 52))
                .foregroundStyle(PPColor.brandGradient)
                .accessibilityHidden(true)
            Text(String(localized: "Welcome to Permission Pulse"))
                .ppFont(.pageTitle)
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                FeatureRow(
                    symbol: "lock.shield",
                    title: String(localized: "Read-only by design"),
                    detail: String(localized: "Inspects permissions, launch agents, and background items. Never changes anything.")
                )
                FeatureRow(
                    symbol: "clock.arrow.circlepath",
                    title: String(localized: "Daily change tracking"),
                    detail: String(localized: "A snapshot a day — see exactly what appeared, changed, or disappeared.")
                )
                FeatureRow(
                    symbol: "hourglass",
                    title: String(localized: "Stale permission alerts"),
                    detail: String(localized: "Flags apps holding permissions you haven't used in months.")
                )
                FeatureRow(
                    symbol: "wifi.slash",
                    title: String(localized: "No network, no analytics"),
                    detail: String(localized: "Everything stays on this Mac. Open source, MIT licensed.")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(String(localized: "Continue")) { step = .fullDiskAccess }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var fdaStep: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            Label(String(localized: "One permission to ask for"), systemImage: "lock.shield")
                .ppFont(.pageTitle)
            Text(String(localized: "Reading the system's permission records (TCC) requires Full Disk Access. Permission Pulse only ever reads — it cannot change permissions, and it never writes outside its own data folder."))
                .ppFont(.body)
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                NumberedStep(number: 1, text: String(localized: "Click Open System Settings below."))
                NumberedStep(number: 2, text: String(localized: "Turn on Permission Pulse under Full Disk Access."))
                NumberedStep(number: 3, text: String(localized: "Quit and reopen Permission Pulse."))
            }
            .vibrancyCard()
            Text(String(localized: "You can skip this — everything except permission scanning still works."))
                .ppFont(.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(String(localized: "Skip for Now")) { onDismiss() }
                Button(String(localized: "Open System Settings")) {
                    SystemSettingsLink.openFullDiskAccess()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: PPSpacing.md) {
            Image(systemName: symbol)
                // Decorative feature glyph — keep fixed size (rule 1)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(title).ppFont(.cardHeader)
                Text(detail)
                    .ppFont(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
            Text("\(number)")
                .ppFont(.badge)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text).ppFont(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Step \(number): \(text)"))
    }
}
```

Notes: window frame in `AppDelegate.showWelcomeWindow()` is already 480×420 — bump to 480×440 to match. If `SystemSettingsLink` is internal-only, it already lives in the same module — no access change needed. Honesty copy preserved (read-only, skip allowed, no overpromising).

- [ ] **Step 2: Build, eyeball both steps (light/dark), commit**

```bash
git add -A && git commit -m "refactor(ui): Welcome → two-step native onboarding with FDA explanation (Thread C T11)"
```

---

### Task 12: Polish, dead-code sweep, verification

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift`, `MenuBarContentView.swift` (motion polish)
- Modify: `scripts/smoke-test.sh` (Thread C checklist)
- Modify: `CLAUDE.md` (Reset window AppKit-drop note no longer true)
- Delete: any orphaned views found by the sweep

- [ ] **Step 1: Motion polish**

- Sidebar badges + dropdown counts: add `.contentTransition(.numericText())` and `.animation(.default, value: <count>)` to the Changes/Stale `.badge` labels and dropdown count rows; wrap with `@Environment(\.accessibilityReduceMotion)` checks where an animation is added (skip the animation when reduced).
- Verify the inspector open/close animates (system-provided); if Task 3 fell back to `HSplitView`, gate its `.animation` on Reduce Motion.

- [ ] **Step 2: Dead-code sweep**

For each of these, grep for references and delete if orphaned: `SectionHeader`, `LiveBadge`, `DetailPageScaffold` (should be fully unused after Tasks 4–7), `PermissionsDisplayItem` (check — its tests cover grant grouping; if the new page's local grouping replaced it, either adopt it in the page instead of the local `AppGrantGroup` or delete type + tests, decide by which is less code), `vibrancyCard` remaining call sites (Welcome + inspectors keep it — that's fine), `PulseDot` (dropped from dropdown header — delete if no references remain). `swift build` must stay warning-clean for unused symbols you can see.

- [ ] **Step 3: Localization + hard-rule audit**

- `grep -rn "Text(\"" Packages/PermissionsUI/Sources | grep -v "String(localized"` — every user-facing literal must go through `String(localized:)` (SF Symbol names and `\(...)` interpolations of already-localized values are fine).
- Confirm Mock badge renders in: dropdown header, window toolbar (mock build run).
- Confirm no file writes were added anywhere (this thread is presentation-only).

- [ ] **Step 4: Smoke-test checklist**

Append a `Thread C — native redesign` block to the HUMAN-ONLY STEPS in `scripts/smoke-test.sh`:

```
# Thread C — native redesign (U: deep links & inspector)
# U1. Dropdown: every status row opens the window on the correct section.
# U2. Permissions: click row → inspector follows; ↑/↓ moves selection + inspector updates.
# U3. ⌘1–⌘6 switch sections; ⌥⌘I toggles inspector; ⌘R rescans from window.
# U4. Overview: attention + count rows navigate; Last Scan time is honest.
# U5. Changes: context-menu dismiss/snooze; badge clears after visiting.
# U6. Stale: context-menu Reveal/Skip forever works.
# U7. FDA-denied run: dropdown attention row → Permissions full-page state → Grant button opens System Settings.
# U8. Settings: 4 tabs render; launch-at-login toggles a Login Items entry; Reset confirms via alert and wipes.
# U9. Welcome: both steps; Open System Settings lands on Full Disk Access.
# U10. All of the above in light + dark; large Dynamic Type in window; clamped in dropdown; Reduce Transparency + Reduce Motion honored.
```

- [ ] **Step 5: Docs touch-up**

In `CLAUDE.md` "Stack — committed" bullet about AppKit drops: remove "and Reset windows" from the one-shot dialog list (Reset confirmation is now a SwiftUI alert in Settings; Welcome remains an AppKit-hosted window). In the UserDefaults section, no changes (launch-at-login state lives in `SMAppService`, not defaults).

- [ ] **Step 6: Full verification**

```bash
cd Packages/PermissionsUI && swift test                       # all green
cd ../PermissionsCore && swift test && cd ../PermissionsStore && swift test && cd ../PermissionsScanners && swift test
cd ../.. && xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse build
```

Expected: all suites PASS, BUILD SUCCEEDED. Then run the app once through smoke-test items U1–U10 yourself; anything that needs a human eye, list it for the user.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "polish(ui): motion, dead-code sweep, smoke checklist, docs for Thread C"
```

---

## Plan self-review notes (already applied)

- **Spec coverage:** archetype/dropdown/inspector/sidebar IA → T3/T4/T5/T9; Overview → T6; Changes/Stale → T7; empty/FDA states → T8; Settings 4 tabs + SMAppService → T10; Welcome → T11; motion/verification → T12; deep-link tests → T1/T2/T9; route timing risk → route-as-state consumed on appear (T3); inspector risk → manual gate + HSplitView fallback (T3).
- **Known intentional deviations** are listed at the top (media-row attribution, per-day grouping, FDA sheet deletion, ⌘W removal).
- **Type consistency:** `AppRoute`/`SidebarItem`/`InspectorSelection`/`InspectorContent`/`DropdownStatusRow` spellings are used identically across T1–T9; `selection: $inspectorSelection` bindings introduced T3, consumed T4/T5.
- **Verify-before-trusting:** `ScannerError` case payloads (T6) and `PermissionRiskSummary.line(for:)` (T6) must be confirmed against source before use — both call sites are named.

