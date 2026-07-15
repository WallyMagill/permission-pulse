# Permission Pulse v0.7.2 Runtime Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live preferences, Reset All Data, and weekly digest scheduling behave exactly as the UI promises without requiring an app restart.

**Architecture:** Snapshot settings become scan-boundary providers, long-lived stores gain explicit reset APIs, and reset becomes an ordered result-bearing state machine. Digest reconciliation returns a typed result so preference UI can debounce schedule edits and display the actual pending state.

**Tech Stack:** Swift 6.3, Swift Testing, Observation, UserDefaults, GRDB, UserNotifications abstractions, SwiftUI.

## Global Constraints

- Complete Workstream A first so app tests are isolated and CI runs the supported toolchain.
- All observable state mutations remain main-actor isolated.
- Reset deletes only Permission Pulse database files and prefixed defaults.
- Preserve macOS-owned window, split-view, and status-item defaults.
- No privileges, protected-database writes, network behavior, or new dependencies.
- User-visible strings remain localized; deployment target remains macOS 14.6.

---

### Task 1: Read retention and stale thresholds at each scan boundary

**Files:**
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift:25-55,61-98,191-206`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:169-180,198-213,240-246`
- Test: `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift`

**Interfaces:**
- Produces: initializer parameters `snapshotRetentionDays: @MainActor () -> Int` and `staleThresholdDays: @MainActor () -> Int`.
- Consumed by: initial and post-reset coordinator construction.

- [ ] **Step 1: Write failing next-scan preference tests**

Add a mutable `PreferencesStore` to the test environment and tests that:

```swift
@Test func changedStaleThresholdAppliesOnNextScan() async throws {
    let path = URL(fileURLWithPath: "/Applications/SixtyDay.app")
    let old = fixedNow().addingTimeInterval(-60 * 86_400)
    let env = try await Environment(now: fixedNow, probe: MockLastUsedProbe(fixed: [path: (old, .spotlight)]))
    env.preferences.staleThresholdDays = 30
    env.viewModel.grants = [demoGrant(bundleID: "com.example.sixty", bundlePath: path)]

    await env.coordinator.onScanCompleted()

    #expect(env.viewModel.staleApps.map(\.app.bundleID) == ["com.example.sixty"])
    #expect(env.viewModel.staleThresholdDays == 30)
}

@Test func changedRetentionAppliesOnNextScan() async throws {
    let env = try await Environment(now: fixedNow)
    _ = try await env.store.writeFullSnapshot(grants: [], launchAgents: [], btmItems: [], at: fixedNow().addingTimeInterval(-20 * 86_400))
    env.preferences.snapshotRetentionDays = 10
    env.viewModel.grants = [demoGrant()]

    await env.coordinator.onScanCompleted()

    #expect(try await env.store.latestSnapshotID(atOrBefore: fixedNow().addingTimeInterval(-15 * 86_400)) == nil)
}
```

- [ ] **Step 2: Verify red tests**

```bash
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/SnapshotCoordinatorTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the coordinator still captures integers at initialization.

- [ ] **Step 3: Replace copied integers with providers**

Use:

```swift
private let snapshotRetentionDays: @MainActor () -> Int
private let staleThresholdDays: @MainActor () -> Int

init(
    viewModel: AppViewModel,
    store: SnapshotStore,
    lastUsedProbe: any LastUsedProbe = LastUsedProbeHybrid(),
    defaults: UserDefaults = .standard,
    calendar: Calendar = .current,
    now: @Sendable @escaping () -> Date = Date.init,
    snapshotRetentionDays: @MainActor @escaping () -> Int = { SnapshotCoordinator.defaultSnapshotRetentionDays },
    staleThresholdDays: @MainActor @escaping () -> Int = { SnapshotCoordinator.defaultStaleThresholdDays },
    dismissedStaleApps: DismissedStaleAppStore? = nil
)
```

At the beginning of `onScanCompleted()`, capture both values and set display state:

```swift
let retentionDays = snapshotRetentionDays()
let thresholdDays = staleThresholdDays()
viewModel.staleThresholdDays = thresholdDays
```

Pass `thresholdDays` into `computeStaleApps(nowDate:thresholdDays:)` and use `retentionDays` for pruning. Wire AppDelegate closures as `{ [weak preferencesStore = self.preferencesStore] in preferencesStore?.snapshotRetentionDays ?? 90 }` and the stale equivalent.

- [ ] **Step 4: Run focused tests**

Run Step 2. Expected: `TEST SUCCEEDED` and both new regressions pass.

- [ ] **Step 5: Commit**

```bash
git add PermissionPulse/PermissionPulse/SnapshotCoordinator.swift \
  PermissionPulse/PermissionPulse/PermissionPulseApp.swift \
  PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift
git commit -m "fix: apply snapshot preferences on the next scan"
```

### Task 2: Add explicit in-memory reset APIs

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DismissedDiffEntryStore.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DismissedStaleAppStore.swift`
- Test: corresponding files under `Packages/PermissionsUI/Tests/PermissionsUITests/`

**Interfaces:**
- Produces: `PreferencesStore.resetToDefaults()`, `DismissedDiffEntryStore.removeAll()`, `DismissedStaleAppStore.removeAll()`.
- Consumed by: Reset state machine in Task 3.

- [ ] **Step 1: Write failing store-reset tests**

```swift
@Test func resetToDefaultsUpdatesLiveValues() {
    let defaults = freshDefaults()
    let store = PreferencesStore(defaults: defaults)
    store.snapshotRetentionDays = 120
    store.staleThresholdDays = 180
    store.digestEnabled = true
    store.digestWeekday = 6
    store.digestHour = 17
    store.digestMinute = 45

    store.resetToDefaults()

    #expect(store.snapshotRetentionDays == 90)
    #expect(store.staleThresholdDays == 90)
    #expect(store.digestEnabled == false)
    #expect(store.digestWeekday == 2)
    #expect(store.digestHour == 9)
    #expect(store.digestMinute == 0)
}
```

Add equivalent tests that populate each dismissal store, call `removeAll()`, and assert both the current object and a reloaded object are empty.

```swift
@Test func removeAllClearsDiffDismissalsInMemoryAndOnDisk() {
    let defaults = freshDefaults()
    let store = DismissedDiffEntryStore(defaults: defaults)
    store.dismissForever(key: "change")
    store.removeAll()
    #expect(store.allEntries().isEmpty)
    #expect(DismissedDiffEntryStore(defaults: defaults).allEntries().isEmpty)
}

@Test func removeAllClearsStaleKeysInMemoryAndOnDisk() {
    let defaults = freshDefaults()
    let store = DismissedStaleAppStore(defaults: defaults)
    store.skipForever(bundleID: "com.example.app")
    store.removeAll()
    #expect(store.allBundleIDs().isEmpty)
    #expect(DismissedStaleAppStore(defaults: defaults).allBundleIDs().isEmpty)
}
```

- [ ] **Step 2: Verify red package tests**

```bash
swift test --package-path Packages/PermissionsUI \
  --filter 'PreferencesStoreTests|DismissedDiffEntryStoreTests|DismissedStaleAppStoreTests'
```

Expected: FAIL because reset methods are absent.

- [ ] **Step 3: Implement reset APIs**

```swift
public func resetToDefaults() {
    snapshotRetentionDays = Self.defaultSnapshotRetentionDays
    staleThresholdDays = Self.defaultStaleThresholdDays
    digestEnabled = Self.defaultDigestEnabled
    digestWeekday = Self.defaultDigestWeekday
    digestHour = Self.defaultDigestHour
    digestMinute = Self.defaultDigestMinute
}
```

```swift
public func removeAll() {
    entries.removeAll()
    persist()
}
```

```swift
public func removeAll() {
    bundleIDs.removeAll()
    persist()
}
```

- [ ] **Step 4: Run focused package tests**

Run Step 2. Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DismissedDiffEntryStore.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/DismissedStaleAppStore.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests
git commit -m "fix: reset live preference and dismissal stores"
```

### Task 3: Replace Boolean reset with an ordered result-bearing state machine

**Files:**
- Modify: `PermissionPulse/PermissionPulse/ResetAllDataService.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:219-270`
- Test: `PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift`

**Interfaces:**
- Produces: `ResetPhase`, `ResetResult`, and `ResetFileManaging`.
- Consumes: Task 2 reset methods and Task 1 live coordinator providers.

- [ ] **Step 1: Write failing cascade and deletion-error tests**

Populate preferences and both dismissal stores, enable/schedule a digest, create main/WAL/SHM files, then assert:

```swift
let result = await env.service.reset()
#expect(result == .completed(scanSucceeded: true))
#expect(env.preferencesStore.digestEnabled == false)
#expect(env.dismissedDiffEntries.allEntries().isEmpty)
#expect(env.dismissedStaleApps.allBundleIDs().isEmpty)
#expect(await env.scheduler.pendingIdentifiers().isEmpty)
#expect(env.releasedStoreCount == 1)
```

Inject a file manager whose `removeItem(at:)` throws and assert:

```swift
#expect(await service.reset() == .failed(phase: .deleteHistory, message: "injected removal failure"))
#expect(reinitCalled == false)
#expect(rescanCalled == false)
```

- [ ] **Step 2: Verify red app tests**

```bash
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/ResetAllDataServiceTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because reset returns `Bool`, swallows removal errors, and cannot clear live stores.

- [ ] **Step 3: Add typed reset contracts**

```swift
enum ResetPhase: Sendable, Equatable {
    case cancelNotifications
    case releaseHistory
    case deleteHistory
    case resetLiveStores
    case clearDefaults
    case recreateHistory
    case rescan
}

enum ResetResult: Sendable, Equatable {
    case completed(scanSucceeded: Bool)
    case failed(phase: ResetPhase, message: String)
}

protocol ResetFileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func removeItem(at url: URL) throws
}
```

Conform `FileManager` in the app target. Extend service initialization with:

```swift
releaseSnapshotStore: @MainActor () -> Void,
preferencesStore: PreferencesStore,
dismissedDiffEntries: DismissedDiffEntryStore,
dismissedStaleApps: DismissedStaleAppStore,
fileManager: any ResetFileManaging = FileManager.default,
rescan: @MainActor () async -> Bool
```

- [ ] **Step 4: Implement ordered reset**

Implement this order: cancel digest/test notification prefixes; call `releaseSnapshotStore`; remove main, `-wal`, and `-shm` when present; reset the three live stores; remove all prefixed defaults; recreate the store; clear every view-model data/diff/review/error/timestamp field; rescan; reconcile disabled digest; return `.completed(scanSucceeded:)`.

On removal or recreation error, return `.failed` with `error.localizedDescription`. Never call reinit/rescan after deletion failure. In AppDelegate, `releaseSnapshotStore` sets both `snapshotCoordinator` and `snapshotStore` to nil.

- [ ] **Step 5: Run reset and app suites**

Run Step 2, then the full `PermissionPulseTests` command from Workstream A. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add PermissionPulse/PermissionPulse/ResetAllDataService.swift \
  PermissionPulse/PermissionPulse/PermissionPulseApp.swift \
  PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift
git commit -m "fix: make reset state complete and observable"
```

### Task 4: Count TCC authorization transitions in digest copy

**Files:**
- Modify: `PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift:150-171`
- Test: `PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift`

**Interfaces:**
- Produces: valid digest body for TCC-only changed diffs.

- [ ] **Step 1: Write the failing TCC-only digest test**

```swift
@Test func composeTCCChangedOnlyProducesChangedSentence() {
    let env = makeEnv(digestEnabled: true, status: .authorized)
    let before = demoGrant(authValue: 2)
    let after = demoGrant(authValue: 3)
    let diff = SnapshotDiffs(
        fromID: SnapshotID(rawValue: 1), toID: SnapshotID(rawValue: 2),
        tcc: TCCGrantsDiff(added: [], removed: [], changed: [DomainChange(before: before, after: after)]),
        btm: BTMItemsDiff(added: [], removed: []),
        launchAgents: LaunchAgentsDiff(added: [], removed: [])
    )

    #expect(env.coordinator.composeDigestBody(diff: diff).body == String(localized: "1 changed in the last week."))
}
```

- [ ] **Step 2: Verify red test**

Run the focused WeeklyDigestCoordinator suite. Expected: FAIL with the current blank-count sentence.

- [ ] **Step 3: Count TCC changed events**

```swift
let changed = diff.tcc.changed.count + diff.btm.changed.count + diff.launchAgents.changed.count
```

Keep the existing localized fragment/sentence construction.

- [ ] **Step 4: Run focused tests and commit**

```bash
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/WeeklyDigestCoordinatorTests CODE_SIGNING_ALLOWED=NO
git add PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift \
  PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift
git commit -m "fix: count TCC transitions in weekly digests"
```

Expected: tests pass before commit.

### Task 5: Reschedule digest day/time edits and surface failures

**Files:**
- Modify: `PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift:19-111`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:95-127`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesViewModel.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift:132-330`
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/MockWeeklyDigestScheduler.swift`
- Test: `PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesViewModelTests.swift`

**Interfaces:**
- Produces: `WeeklyDigestCoordinator.ScheduleResult`, `PreferencesViewModel.scheduleDidChange()`, and `.failed(String)` authorization hint.

- [ ] **Step 1: Add failing reconciliation and debounce tests**

Test that an enabled digest changed from Monday 09:00 to Friday 17:45 leaves exactly one pending request whose recorded action has `weekday: 6, hour: 17, minute: 45`, and `nextWeeklyFireDate` refreshes. Add a mock scheduler `nextScheduleError` seam and assert the UI hint becomes `.failed("injected scheduling failure")`. In UI tests, inject `.zero` debounce and call `scheduleDidChange()` three times; assert the callback runs once.

- [ ] **Step 2: Verify red suites**

```bash
swift test --package-path Packages/PermissionsUI --filter PreferencesViewModelTests
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/WeeklyDigestCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because schedule changes have no callback/result and coordinator swallows scheduling errors.

- [ ] **Step 3: Return a typed schedule result**

```swift
enum ScheduleResult: Sendable, Equatable {
    case disabled
    case scheduled(nextFire: Date?)
    case notAuthorized
    case failed(String)
}
```

Change `reconcileSchedule()` to return `ScheduleResult`; after scheduling, query `nextWeeklyFireDate()`. Convert thrown scheduling errors to `.failed(error.localizedDescription)` while retaining OSLog.

- [ ] **Step 4: Add debounced preference reconciliation**

Extend `AuthorizationHint` with `.failed(String)`. Add:

```swift
private let onDigestScheduleChange: @MainActor () async -> AuthorizationHint
private let scheduleDebounce: Duration
private var scheduleTask: Task<Void, Never>?

public func scheduleDidChange() {
    guard store.digestEnabled else { return }
    scheduleTask?.cancel()
    scheduleTask = Task { @MainActor in
        try? await Task.sleep(for: scheduleDebounce)
        guard !Task.isCancelled else { return }
        authorizationHint = await onDigestScheduleChange()
        nextWeeklyFireDate = await onFetchNextFireDate()
    }
}
```

Default debounce is `.milliseconds(300)`; tests inject `.zero`. Picker and DatePicker setters persist the new value and call `vm.scheduleDidChange()`. Render `.failed` as an orange localized status row with a Retry button calling `scheduleDidChange()`.

- [ ] **Step 5: Add mock failure control and run tests**

Add `setNextScheduleError(_:)` to `MockWeeklyDigestScheduler`; `scheduleWeekly` throws and clears the injected error once. Run both Step 2 suites and the full app tests. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift \
  PermissionPulse/PermissionPulse/PermissionPulseApp.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/PreferencesViewModel.swift \
  Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift \
  Packages/PermissionsScanners/Sources/PermissionsScanners/MockWeeklyDigestScheduler.swift \
  Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesViewModelTests.swift \
  PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift
git commit -m "fix: reconcile weekly digest schedule edits"
```

### Task 6: Document and verify runtime correctness

**Files:**
- Modify: `README.md`
- Modify: `docs/03-architecture.md`
- Modify: `docs/07-build-and-test.md`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: accurate preference/reset/digest behavior documentation.

- [ ] **Step 1: Document behavior**

State that scan preferences apply at the next scan boundary, Reset clears both live and persisted state plus SQLite sidecars, and digest schedule errors retain the selected time and expose retry.

- [ ] **Step 2: Run the workstream gate**

```bash
swift test --package-path Packages/PermissionsUI
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
git diff --check
```

Expected: package and app tests pass; diff check is clean.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/03-architecture.md docs/07-build-and-test.md
git commit -m "docs: describe live settings and reset recovery"
```

## Workstream B Exit Gate

- [ ] Retention and stale thresholds affect the next scan without coordinator recreation.
- [ ] Reset clears live and persisted state and reports storage failures honestly.
- [ ] Reset cannot recreate an enabled digest from stale in-memory preferences.
- [ ] TCC-only digests contain valid changed counts.
- [ ] Digest day/time edits debounce, replace pending requests, refresh next-fire date, and expose retryable failure.
