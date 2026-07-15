# Permission Pulse v0.7.2 Data Fidelity and Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make application identity, scanner coverage, historical diffs, and search accurately represent the evidence Permission Pulse has collected.

**Architecture:** Centralize application stable keys in PermissionsCore, return typed scanner outputs with degradation warnings, make domain availability the single UI/snapshot truth, and migrate history to schema v5 with an explicit disabled-state capture marker. Render all diff categories through one searchable row model.

**Tech Stack:** Swift 6.3, Swift Testing, AppKit `NSWorkspace`, GRDB migrations, Observation, SwiftUI.

## Global Constraints

- Complete Workstreams A and B first.
- TCC/BTM/launchd access remains read-only; no privilege escalation or system writes.
- Partial evidence under-flags and never generates a historical removal.
- No network identity/reputation lookups or new dependencies.
- Preserve v4 snapshots and legacy dismissal choices.
- Keep the four-package dependency direction and macOS 14.6 deployment target.
- Localize visible state, warning, transition, search, and accessibility copy.

---

### Task 1: Centralize stable application identity and migrate stale dismissals

**Files:**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/AppIdentity.swift`
- Inspect only: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionGrant.swift:28-44` to preserve its persisted dismissal-key contract
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DismissedStaleAppStore.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift:12-69`
- Test: `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionGrantIdentityTests.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/DismissedStaleAppStoreTests.swift`

**Interfaces:**
- Produces: `AppIdentity.stableKey: String?`, key-based stale dismissal APIs, and legacy-key migration.
- Consumed by: scanner dedupe, stale computation, SwiftUI identity, and Task 2 resolution.

- [ ] **Step 1: Write failing stable-key tests**

```swift
@Test func bundleIdentityUsesPrefixedBundleKey() {
    let app = AppIdentity(bundleID: "com.example.app", displayName: "App", bundlePath: URL(fileURLWithPath: "/Applications/App.app"))
    #expect(app.stableKey == "bundle:com.example.app")
}

@Test func pathOnlyIdentityUsesStandardizedPathKey() {
    let app = AppIdentity(bundleID: "", displayName: "Tool", bundlePath: URL(fileURLWithPath: "/Applications/Sub/../Tool.app"))
    #expect(app.stableKey == "path:/Applications/Tool.app")
}

@Test func identityWithoutBundleOrPathHasNoStableKey() {
    #expect(AppIdentity(bundleID: "", displayName: "Unknown").stableKey == nil)
}
```

Add UI-store tests that seed `UserDefaults` with `["com.example.legacy"]`, initialize the store, assert `contains(stableKey: "bundle:com.example.legacy")`, trigger persistence, and assert disk now contains the prefixed key.

- [ ] **Step 2: Verify red package tests**

```bash
swift test --package-path Packages/PermissionsCore --filter PermissionGrantIdentityTests
swift test --package-path Packages/PermissionsUI --filter DismissedStaleAppStoreTests
```

Expected: FAIL because stable keys and key-based APIs do not exist.

- [ ] **Step 3: Implement canonical keys and migration**

```swift
public var stableKey: String? {
    if !bundleID.isEmpty { return "bundle:\(bundleID)" }
    guard let bundlePath else { return nil }
    let path = bundlePath.standardizedFileURL.path(percentEncoded: false)
    return path.isEmpty ? nil : "path:\(path)"
}
```

Do not change `PermissionGrant.appKey` or `identityKey`: existing dismissed-diff keys depend on their unprefixed format. Task 2 uses `AppIdentity.stableKey` directly for scanner dedupe and stale grouping. Replace stale store APIs with `contains(stableKey:)`, `skipForever(stableKey:)`, and `unskip(stableKey:)`. On load:

```swift
let migrated = strings.map { key in
    key.hasPrefix("bundle:") || key.hasPrefix("path:") ? key : "bundle:\(key)"
}
return Set(migrated)
```

Use `stableKey` for StaleApps filtering, `ForEach` identity, and skip actions; exclude nil keys.

- [ ] **Step 4: Run both package suites and commit**

```bash
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsUI
git add Packages/PermissionsCore/Sources/PermissionsCore/AppIdentity.swift \
  Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionGrantIdentityTests.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DismissedStaleAppStore.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/DismissedStaleAppStoreTests.swift
git commit -m "fix: give stale apps stable bundle and path identities"
```

Expected: both suites pass before commit.

### Task 2: Retain resolved application URLs in TCC identities

**Files:**
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift:188-225`
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift:191-205`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCScannerSQLiteTests.swift`
- Test: `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift`

**Interfaces:**
- Produces: injected `ApplicationResolving` seam and bundle identities containing resolved URLs.
- Consumes: `AppIdentity.stableKey` from Task 1.

- [ ] **Step 1: Write failing resolution and stale-integration tests**

Define a test resolver mapping `com.example.installed` to `/Applications/Installed.app`. Assert a client-type-0 fixture produces that bundle path. Add a coordinator test that feeds the scanner-produced grant into stale computation without manually adding a path and expects it to appear when the last-used probe is old.

```swift
struct TestApplicationResolver: ApplicationResolving {
    let urls: [String: URL]
    func applicationURL(forBundleIdentifier bundleID: String) async -> URL? { urls[bundleID] }
}

let expected = URL(fileURLWithPath: "/Applications/Installed.app")
let scanner = TCCScannerSQLite(
    databaseURLs: [dbURL],
    applicationResolver: TestApplicationResolver(urls: ["com.example.installed": expected])
)
let output = try await scanner.scan()
#expect(output.items.first { $0.app.bundleID == "com.example.installed" }?.app.bundlePath == expected)
```

- [ ] **Step 2: Verify red tests**

```bash
swift test --package-path Packages/PermissionsScanners --filter TCCScannerSQLiteTests
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/SnapshotCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: bundle client path is nil and the stale candidate is dropped.

- [ ] **Step 3: Add one resolver call for URL and name**

```swift
protocol ApplicationResolving: Sendable {
    func applicationURL(forBundleIdentifier bundleID: String) async -> URL?
}

struct WorkspaceApplicationResolver: ApplicationResolving {
    func applicationURL(forBundleIdentifier bundleID: String) async -> URL? {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
    }
}
```

Make row mapping async or pre-resolve unique bundle IDs before mapping. Change scanner dedupe to build its app portion from `grant.app.stableKey ?? grant.appKey`, leaving `PermissionGrant.identityKey` unchanged for stored dismissal compatibility. For client type 0, construct:

```swift
let url = resolvedURLs[client]
let name = url.map { FileManager.default.displayName(atPath: $0.path(percentEncoded: false)) }
return AppIdentity(bundleID: client, displayName: name.flatMap { $0.isEmpty ? nil : $0 } ?? client, bundlePath: url)
```

Group stale grants by nonnil `stableKey`, not bundle ID.

- [ ] **Step 4: Run focused/full scanner and app tests, then commit**

```bash
swift test --package-path Packages/PermissionsScanners
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
git add Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCScannerSQLiteTests.swift \
  PermissionPulse/PermissionPulse/SnapshotCoordinator.swift \
  PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift
git commit -m "fix: resolve TCC bundle paths for stale detection"
```

### Task 3: Return typed scanner output and degradation warnings

**Files:**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift`
- Modify: all live/mock scanner implementations under `Packages/PermissionsScanners/Sources/PermissionsScanners/`
- Modify: scanner tests under `Packages/PermissionsScanners/Tests/PermissionsScannersTests/`

**Interfaces:**
- Produces: `ScannerOutput<Item>`, `ScannerWarning`, `ScannerSource`, and updated scanner protocols.
- Consumed by: ScanCoordinator in Task 4.

- [ ] **Step 1: Write failing partial-output contract tests**

Update TCC multi-database tests so one fixture succeeds and one injected URL fails; expect one warning and retained items. Update LaunchAgent tests so one unreadable existing source yields retained items plus one warning. Update mocks to construct explicit complete/degraded outputs.

```swift
let output = try await TCCScannerSQLite(databaseURLs: [readableURL, missingURL]).scan()
#expect(!output.items.isEmpty)
#expect(output.warnings.count == 1)

let launchOutput = try await LaunchAgentScannerFS(sources: [readableSource, unreadableSource]).scan()
#expect(launchOutput.items.map(\.label).contains("com.test.partial"))
#expect(launchOutput.warnings.count == 1)
```

- [ ] **Step 2: Verify compile/test failure**

```bash
swift test --package-path Packages/PermissionsScanners
```

Expected: FAIL until protocols and implementations return typed outputs.

- [ ] **Step 3: Add core output types**

```swift
public enum ScannerSource: Sendable, Equatable {
    case userTCCDatabase
    case systemTCCDatabase
    case userLaunchAgents
    case libraryLaunchAgents
    case libraryLaunchDaemons
    case entries
}

public struct ScannerWarning: Sendable, Equatable {
    public let source: ScannerSource
    public let omittedCount: Int?

    public init(source: ScannerSource, omittedCount: Int? = nil) {
        self.source = source
        self.omittedCount = omittedCount
    }
}

public struct ScannerOutput<Item: Sendable>: Sendable {
    public let items: [Item]
    public let warnings: [ScannerWarning]

    public init(items: [Item], warnings: [ScannerWarning] = []) {
        self.items = items
        self.warnings = warnings
    }
}
```

Make `ScannerError` Equatable. Change protocols to return `ScannerOutput<PermissionGrant>`, `ScannerOutput<LaunchAgentItem>`, and `ScannerOutput<BTMItem>`.

- [ ] **Step 4: Migrate implementations without discarding partial evidence**

TCC maps failed database URLs to user/system source warnings; if all fail it throws the first mapped scanner error. LaunchAgent scanner records a warning for each existing unreadable source; absent directories remain normal. BTM returns complete output or throws. Mocks accept `warnings` in their initializers and return them with items.

- [ ] **Step 5: Run the scanner suite and commit**

```bash
swift test --package-path Packages/PermissionsScanners
git add Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners \
  Packages/PermissionsScanners/Tests/PermissionsScannersTests
git commit -m "feat: report partial scanner coverage"
```

Expected: all scanner tests pass.

### Task 4: Make availability the single source of truth and block degraded snapshots

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/ScanAvailability.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/ScanAvailabilityBanner.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AttentionState.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/OverviewPage.swift`
- Modify: `PermissionPulse/PermissionPulse/ScanCoordinator.swift`
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift`
- Test: `PermissionPulse/PermissionPulseTests/ScanCoordinatorTests.swift`
- Test: `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAvailabilityTests.swift`

**Interfaces:**
- Produces: `ScanAvailability`, three AppViewModel availability properties, and shared banner.
- Consumes: `ScannerOutput` from Task 3.

- [ ] **Step 1: Write failing state-transition tests**

Test complete output replaces data and records `.complete`; degraded output replaces the live list, records warnings, and causes `SnapshotCoordinator` to skip its write; failed output preserves the previous list and records `.failed(lastSuccessful:error:)`. Test menu-bar/Overview attention is non-clean for degraded and failed domains.

- [ ] **Step 2: Verify red UI/app tests**

```bash
swift test --package-path Packages/PermissionsUI --filter 'AppViewModelAvailabilityTests|AttentionStateTests'
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/ScanCoordinatorTests \
  -only-testing:PermissionPulseTests/SnapshotCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because only nullable errors exist and partial warnings are invisible.

- [ ] **Step 3: Add availability model**

```swift
public enum ScanAvailability: Sendable, Equatable {
    case never
    case complete(lastUpdated: Date)
    case degraded(lastUpdated: Date, warnings: [ScannerWarning])
    case failed(lastSuccessful: Date?, error: ScannerError)

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}
```

Add `tccAvailability`, `btmAvailability`, and `launchAgentAvailability` to AppViewModel. Add `.degradedData` and `.staleData` to `AttentionState`, with failed/schema/FDA states retaining higher precedence. Remove duplicated mutable scan-error state; expose compatibility computed error accessors only while call sites migrate in the same task.

- [ ] **Step 4: Apply coordinator transitions and snapshot gate**

Use one captured scan time. Complete/degraded outputs replace items and set the corresponding state. Failure retains items and carries forward the last complete/degraded timestamp. Map unknown thrown errors to `.temporarilyUnavailable(reason:)`, not permission denial. Require all three availability values to be `.complete` in `scanFullySucceeded()`.

- [ ] **Step 5: Render truthful banners and accessibility state**

`ScanAvailabilityBanner` maps machine warning sources to localized copy and displays complete/degraded/last-known timestamps. Insert it in Permissions, Launch Agents, and Background Items pages. Update Overview and menu-bar accessibility labels to announce degraded or stale data without depending on color.

- [ ] **Step 6: Run focused/full suites and commit**

```bash
swift test --package-path Packages/PermissionsUI
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
git add Packages/PermissionsUI/Sources/PermissionsUI/ScanAvailability.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/ScanAvailabilityBanner.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/AttentionState.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/OverviewPage.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests \
  PermissionPulse/PermissionPulse/ScanCoordinator.swift \
  PermissionPulse/PermissionPulse/SnapshotCoordinator.swift \
  PermissionPulse/PermissionPulseTests
git commit -m "fix: distinguish complete degraded and stale scan data"
```

### Task 5: Render TCC transitions and make Recent Changes searchable

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift:117-127`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift:27-39,119-140,525-573`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/DiffEntryKeyTests.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/WhatChangedViewModelTests.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAccessibilityTests.swift`

**Interfaces:**
- Produces: `ChangeRow.Kind.permissionChanged`, searchable row summaries, and section-aware search visibility.

- [ ] **Step 1: Write failing transition/count/search tests**

```swift
let change = DomainChange(before: grant(authValue: 2), after: grant(authValue: 3))
let kind = ChangeRow.Kind.permissionChanged(change)
#expect(ChangeRow.summary(for: kind).contains("Allowed → Limited"))
#expect(DiffEntryKey.key(for: kind).contains("2-3"))
```

Create a TCC-only changed diff and assert `recentChangeEventCount == 1`. Extract/filter row kinds with query `limited` and assert the transition remains while unrelated rows do not. Assert Overview reports `showsSearch == false` and Recent Changes reports true.

- [ ] **Step 2: Verify red UI tests**

```bash
swift test --package-path Packages/PermissionsUI \
  --filter 'DiffEntryKeyTests|WhatChangedViewModelTests|AppViewModelAccessibilityTests'
```

Expected: FAIL because TCC changed rows are omitted and Recent Changes ignores search.

- [ ] **Step 3: Add TCC transition rendering**

Add `case permissionChanged(DomainChange<PermissionGrant>)`, include it in the orange changed indicator, and map auth values with:

```swift
private static func authorizationLabel(_ value: Int) -> String {
    switch value {
    case 2: String(localized: "Allowed")
    case 3: String(localized: "Limited")
    default: String(localized: "Value \(value)")
    }
}
```

Summary copy is `Permission changed: <service> for <app> (<before> → <after>)`. Dismissal key is `tcc-changed|<identity>|<before>-<after>`. Include `diff.changed.map(ChangeRow.Kind.permissionChanged)` in `tccRows` and count TCC changed in `recentChangeEventCount`.

- [ ] **Step 4: Use one rendered-row filter for Recent Changes**

Make `DiffTabView` accept `searchText: String = ""`. Build all row kinds first, then filter by `ChangeRow.searchText(for:)`, which concatenates localized summary plus app/service/label/path/developer/identifier fields. Pass `searchText` from `RecentChangesDetailPage`.

Make `.searchable` conditional:

```swift
@ViewBuilder private var searchableSidebar: some View {
    if (section ?? .overview) == .overview {
        DetailSidebar(selection: $section)
    } else {
        DetailSidebar(selection: $section)
            .searchable(text: $searchText, placement: .sidebar, prompt: searchPrompt)
    }
}
```

- [ ] **Step 5: Run UI tests and commit**

```bash
swift test --package-path Packages/PermissionsUI
git add Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests
git commit -m "feat: show and search TCC authorization changes"
```

Expected: all UI tests pass.

### Task 6: Persist LaunchAgent disabled state with a compatible v5 migration

**Files:**
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift`
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/LaunchAgentItem.swift:24-29`
- Test: `Packages/PermissionsStore/Tests/PermissionsStoreTests/LaunchAgentsDiffTests.swift`
- Create: `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotV4Fixture.swift`

**Interfaces:**
- Produces: schema version 5, persisted `is_disabled`, per-snapshot capture marker, and compatibility-aware LaunchAgent comparison.

- [ ] **Step 1: Build a real v4 fixture and failing migration tests**

`SnapshotV4Fixture.make(at:)` creates the v1-v4 tables/columns, schema version 4, one snapshot, and one disabled-relevant LaunchAgent row without v5 columns. Tests open it through `SnapshotStore`, assert schema 5/history retained, and assert legacy-to-v5 disabled-only comparison has no change. Two new snapshots with false then true must produce one change.

- [ ] **Step 2: Verify red store tests**

```bash
swift test --package-path Packages/PermissionsStore --filter LaunchAgentsDiffTests
```

Expected: FAIL because schema remains 4 and disabled state is not stored.

- [ ] **Step 3: Add transactional migration v5**

```swift
migrator.registerMigration("v5") { db in
    try db.alter(table: "launch_agents") { table in
        table.add(column: "is_disabled", .integer).notNull().defaults(to: false)
    }
    try db.alter(table: "snapshots") { table in
        table.add(column: "launch_agent_disabled_captured", .integer).notNull().defaults(to: false)
    }
    try db.execute(sql: "UPDATE schema_version SET version = 5")
}
```

New snapshot inserts set `launch_agent_disabled_captured = 1`; legacy rows retain 0. Include `is_disabled` in LaunchAgent INSERT/SELECT and pass it into `LaunchAgentItem`.

- [ ] **Step 4: Add compatibility-aware diff equivalence**

Extend generic `computeDiff` with an `equivalent: (Item, Item) -> Bool` closure. For LaunchAgents, query capture markers for both snapshot IDs and use:

```swift
private static func launchAgentsEquivalent(
    _ lhs: LaunchAgentItem,
    _ rhs: LaunchAgentItem,
    compareDisabled: Bool
) -> Bool {
    lhs.label == rhs.label
        && lhs.sourceDirectory == rhs.sourceDirectory
        && lhs.programPath == rhs.programPath
        && lhs.programArguments == rhs.programArguments
        && lhs.runAtLoad == rhs.runAtLoad
        && lhs.keepAlive == rhs.keepAlive
        && (!compareDisabled || lhs.isDisabled == rhs.isDisabled)
}
```

Set `compareDisabled` only when both snapshot markers are true. Other domains pass `==`.

- [ ] **Step 5: Run full store tests and commit**

```bash
swift test --package-path Packages/PermissionsStore
git add Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift \
  Packages/PermissionsStore/Tests/PermissionsStoreTests/LaunchAgentsDiffTests.swift \
  Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotV4Fixture.swift \
  Packages/PermissionsCore/Sources/PermissionsCore/LaunchAgentItem.swift
git commit -m "feat: persist LaunchAgent disabled history in schema v5"
```

Expected: v4 migration, legacy comparison, and v5 transition tests pass.

### Task 7: Documentation, full verification, and FDA checklist

**Files:**
- Modify: `README.md`
- Modify: `docs/03-architecture.md`
- Modify: `docs/05-risks-and-mitigations.md`
- Modify: `docs/07-build-and-test.md`
- Modify: `docs/09-roadmap.md`
- Modify: `scripts/smoke-test.sh`

**Interfaces:**
- Consumes: Tasks 1-6 and Workstreams A-B.
- Produces: accurate schema/coverage/search documentation and v0.7.2 human gates.

- [ ] **Step 1: Update architecture and risk documentation**

Document stable key formats, `ScannerOutput`, complete/degraded/failed state behavior, snapshot suppression during degradation, schema v5 compatibility markers, TCC transition rows, and functional Recent Changes search.

- [ ] **Step 2: Extend the human checklist**

Add explicit FDA steps for complete user/system TCC reads, a controlled degraded source, bundle-ID stale candidates, independent path-only clients, visible TCC authorization transitions, and VoiceOver announcements for degraded/last-known data. Keep Intel execution marked unverified unless real Intel hardware is used.

- [ ] **Step 3: Run the entire repository gate**

```bash
for package in PermissionsCore PermissionsScanners PermissionsStore PermissionsUI; do
  swift test --package-path "Packages/$package"
done
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
rm -rf /tmp/permission-pulse-v072-final
PERMISSION_PULSE_PACKAGE_TESTING=1 \
  scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v072-final
scripts/verify-release.sh \
  /tmp/permission-pulse-v072-final/PermissionPulse-v0.7.2-TESTING-DIRTY.app.zip 0.7.2 12
gitleaks git --no-banner --redact .
git diff --check
```

Expected: all 267 baseline tests plus new regressions pass, analyzer succeeds, artifact verifies, no secrets are found, and diff check is clean. Record the new exact test count in docs.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/03-architecture.md docs/05-risks-and-mitigations.md \
  docs/07-build-and-test.md docs/09-roadmap.md scripts/smoke-test.sh
git commit -m "docs: document v0.7.2 data fidelity guarantees"
```

- [ ] **Step 5: Run the clean-tree release artifact gate**

```bash
rm -rf /tmp/permission-pulse-v072-final-clean
scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v072-final-clean
scripts/verify-release.sh \
  /tmp/permission-pulse-v072-final-clean/PermissionPulse-v0.7.2.app.zip 0.7.2 12
```

Expected: publishable zip/checksum/manifest are produced and verify with no testing override.

## Workstream C Exit Gate

- [ ] Bundle and path-only clients have stable independent identity and migrated dismissals.
- [ ] Installed bundle-ID apps retain paths and can reach stale detection.
- [ ] Partial scans are visibly degraded and never persisted as snapshots.
- [ ] Failed scans retain and label last-known data.
- [ ] TCC authorization transitions render, count, dismiss, search, and digest consistently.
- [ ] Schema v5 retains v4 history, suppresses false upgrade transitions, and detects real disabled changes.
- [ ] Overview has no false search affordance and Recent Changes search covers every rendered row kind.
