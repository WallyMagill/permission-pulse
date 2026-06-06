# Workstream 1 — Trust & Correctness (P0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the seven P0 correctness/trust defects (C1–C7) so Permission Pulse shows correct data and fails loudly instead of silently.

**Architecture:** Each task is an independent, committable fix. Pure-logic changes (C1, C5, C7) get full RED→GREEN unit tests. View-model and coordinator changes get unit tests at the seam (injected mocks). SwiftUI view wiring and the live CoreMediaIO path are not unit-tested in this codebase (only view models / mocks are) — those steps use build + manual verification, matching the project's existing test strategy.

**Tech Stack:** Swift 6.0 (MainActor-by-default), SwiftUI, GRDB 7.10, Swift Testing (`import Testing`), Xcode 26. Four local SwiftPM packages + an Xcode app target.

**Source spec:** `docs/superpowers/specs/2026-06-06-app-quality-audit-design.md` (Workstream 1).

**Conventions:**
- Commit attribution is disabled globally — do **not** add a `Co-Authored-By` trailer.
- All new user-facing strings go through `String(localized:)`.
- Package tests run with `swift test --package-path <pkg> --filter <name>`. App-target tests run with `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:<TestTarget/Suite>`.

---

## File Structure

**Task 1 (C1):**
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift` (diff cutoffs)
- Test: `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift` (+ `calendar` param on the `Environment` helper, + 1 test)

**Task 2 (C5):**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift` (+`.temporarilyUnavailable` case)
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift` (`mapDatabaseError`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift` (handle new case — compile fix)
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/ScannerErrorMappingTests.swift` (new)

**Task 3 (C7):**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` (+`staleThresholdDays`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift` (param + interpolation)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (subtitle + pass param)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (set from preferences)
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelStaleThresholdTests.swift` (new)

**Task 4 (C3):**
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/LaunchAgentScannerFS.swift` (propagate dir-unreadable, log level)
- Modify: `PermissionPulse/PermissionPulse/ScanCoordinator.swift` (`LaunchAgentScanResult.error`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` (+`launchAgentScanError`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (surface error on the Launch Agents page)
- Test: `PermissionPulse/PermissionPulseTests/ScanCoordinatorTests.swift` (new)

**Task 5 (C2):**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` (+`snapshotStoreUnavailable`, +`diffUnavailable`)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (set `snapshotStoreUnavailable`)
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift` (set `diffUnavailable` on diff error)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift` (error state)
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAvailabilityTests.swift` (new)

**Task 6 (C4):**
- Modify: `PermissionPulse/PermissionPulse/ResetAllDataService.swift` (surface re-init failure)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (`performReset` error feedback)
- Test: `PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift` (+1 test)

**Task 7 (C6):**
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/MediaUseObserverCMIO.swift` (poll all enumerated devices; track degraded)
- Verification: build + manual (live hardware path is not unit-testable).

---

## Task 1: C1 — Anchor diff windows to calendar-day boundaries

**Problem:** `refreshDiffsAndStale` picks the diff baseline with a rolling `now − 24h`/`now − 7d`, but snapshots are written once per calendar day, so the "yesterday" diff silently depends on the time of day.

**Files:**
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift:137-139`
- Test: `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift`

- [ ] **Step 1: Add a `calendar` parameter to the test `Environment` helper**

In `SnapshotCoordinatorTests.swift`, the `Environment.init` currently hardcodes `calendar: Calendar(identifier: .gregorian)`. Make it injectable so the boundary test can pin a timezone. Replace the `init` signature and the `calendar:` argument:

```swift
        init(
            now: @Sendable @escaping () -> Date,
            probe: any LastUsedProbe = MockLastUsedProbe(),
            calendar: Calendar = Calendar(identifier: .gregorian),
            snapshotRetentionDays: Int = SnapshotCoordinator.defaultSnapshotRetentionDays,
            staleThresholdDays: Int = SnapshotCoordinator.defaultStaleThresholdDays,
            dismissedStaleApps: DismissedStaleAppStore? = nil
        ) async throws {
            self.store = try SnapshotStore.inMemory()
            self.viewModel = AppViewModel()
            self.defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
            self.coordinator = SnapshotCoordinator(
                viewModel: viewModel,
                store: store,
                lastUsedProbe: probe,
                defaults: defaults,
                calendar: calendar,
                now: now,
                snapshotRetentionDays: snapshotRetentionDays,
                staleThresholdDays: staleThresholdDays,
                dismissedStaleApps: dismissedStaleApps
            )
        }
```

- [ ] **Step 2: Write the failing test**

Add this `@Test` inside `struct SnapshotCoordinatorTests` (after `pushesDiffsAndStaleAppsToViewModelAfterWrite`):

```swift
    @Test func yesterdayDiffUsesCalendarDayBoundaryNotRollingWindow() async throws {
        // Regression for C1. "Now" is early morning today; a snapshot taken
        // yesterday afternoon is only ~18h old, so the old rolling 24h window
        // wrongly excluded it. The calendar-day boundary must include it.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let startOfToday = cal.startOfDay(for: base)
        let nowMorning = startOfToday.addingTimeInterval(8 * 3600)      // today 08:00 UTC
        let yesterdayAfternoon = startOfToday.addingTimeInterval(-10 * 3600) // yesterday 14:00 UTC

        let env = try await Environment(now: { nowMorning }, calendar: cal)
        _ = try await env.store.writeFullSnapshot(
            grants: [demoGrant(bundleID: "com.example.old")],
            launchAgents: [], btmItems: [],
            at: yesterdayAfternoon
        )

        env.viewModel.grants = [demoGrant(bundleID: "com.example.new")]
        await env.coordinator.onScanCompleted()

        #expect(env.viewModel.latestDiffYesterday != nil)
        #expect(env.viewModel.latestDiffYesterday?.hasContent == true)
    }
```

- [ ] **Step 3: Run the test to verify it FAILS**

Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/SnapshotCoordinatorTests/yesterdayDiffUsesCalendarDayBoundaryNotRollingWindow 2>&1 | tail -20`
Expected: FAIL — `latestDiffYesterday` is `nil` (rolling 24h window excludes the 18h-old snapshot).

- [ ] **Step 4: Implement the calendar-day boundary fix**

In `SnapshotCoordinator.swift`, in `refreshDiffsAndStale`, replace:

```swift
        let nowDate = now()
        let yesterdayCutoff = nowDate.addingTimeInterval(-Self.yesterdayWindowSeconds)
        let weekCutoff = nowDate.addingTimeInterval(-Self.weekWindowSeconds)
```

with:

```swift
        let nowDate = now()
        // Anchor diff baselines to calendar-day boundaries, not a rolling
        // window, because snapshots are written at most once per calendar day.
        // `latestSnapshotID(atOrBefore:)` is inclusive (<=): today's snapshot
        // has a timestamp after startOfToday and is excluded; the most recent
        // prior-day snapshot is <= startOfToday and is selected. (C1)
        let startOfToday = calendar.startOfDay(for: nowDate)
        let yesterdayCutoff = startOfToday
        let weekCutoff = calendar.date(byAdding: .day, value: -7, to: startOfToday)
            ?? startOfToday.addingTimeInterval(-Self.weekWindowSeconds)
```

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/SnapshotCoordinatorTests 2>&1 | tail -20`
Expected: PASS — the new test and all existing `SnapshotCoordinatorTests` pass (the existing `pushesDiffsAndStaleAppsToViewModelAfterWrite` seeds at −36h, which both windows include).

- [ ] **Step 6: Commit**

```bash
git add PermissionPulse/PermissionPulse/SnapshotCoordinator.swift PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift
git commit -m "fix(snapshot): anchor diff windows to calendar-day boundaries (C1)"
```

---

## Task 2: C5 — Map TCC database errors to accurate advice

**Problem:** `TCCScannerSQLite.mapDatabaseError` funnels every SQLite error to "grant Full Disk Access," misdirecting users when the DB is corrupt or locked.

**Files:**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift:3-17`
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift:243-251`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift:15-24`
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/ScannerErrorMappingTests.swift` (new)

- [ ] **Step 1: Add the `.temporarilyUnavailable` case to `ScannerError`**

In `Scanners.swift`, replace the enum and its `errorDescription`:

```swift
public enum ScannerError: Error, Sendable {
    case permissionDenied(reason: String)
    case schemaMismatch(detail: String)
    case unsupportedOnThisOS(detail: String)
    case temporarilyUnavailable(reason: String)
}

extension ScannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let reason):    reason
        case .schemaMismatch(let detail):      detail
        case .unsupportedOnThisOS(let detail): detail
        case .temporarilyUnavailable(let reason): reason
        }
    }
}
```

- [ ] **Step 2: Make `mapDatabaseError` internal and write the failing test**

First, in `TCCScannerSQLite.swift`, change the function from `private static` to `static` (so `@testable` can reach it). Leave its body for now — replace just the signature line:

```swift
    static func mapDatabaseError(_ error: DatabaseError) -> ScannerError {
```

Create `Packages/PermissionsScanners/Tests/PermissionsScannersTests/ScannerErrorMappingTests.swift`:

```swift
import Foundation
import Testing
import GRDB
import PermissionsCore
@testable import PermissionsScanners

@Suite struct ScannerErrorMappingTests {
    @Test func cantOpenMapsToPermissionDenied() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_CANTOPEN))
        guard case .permissionDenied = mapped else {
            Issue.record("Expected .permissionDenied, got \(mapped)"); return
        }
    }

    @Test func corruptMapsToSchemaMismatch() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_CORRUPT))
        guard case .schemaMismatch = mapped else {
            Issue.record("Expected .schemaMismatch, got \(mapped)"); return
        }
    }

    @Test func busyMapsToTemporarilyUnavailable() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_BUSY))
        guard case .temporarilyUnavailable = mapped else {
            Issue.record("Expected .temporarilyUnavailable, got \(mapped)"); return
        }
    }
}
```

- [ ] **Step 3: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsScanners --filter ScannerErrorMappingTests 2>&1 | tail -20`
Expected: FAIL — `corruptMapsToSchemaMismatch` and `busyMapsToTemporarilyUnavailable` fail because the current body always returns `.permissionDenied`.

- [ ] **Step 4: Implement the real mapping**

In `TCCScannerSQLite.swift`, replace the body of `mapDatabaseError` and add the two reason strings next to `permissionDeniedReason`:

```swift
    static func mapDatabaseError(_ error: DatabaseError) -> ScannerError {
        // FDA-missing surfaces as CANTOPEN/AUTH/PERM/READONLY and is the
        // dominant cause; corruption and transient locks need different advice
        // so we don't send users on a Full-Disk-Access wild goose chase. (C5)
        switch error.resultCode.primaryResultCode {
        case .SQLITE_CANTOPEN, .SQLITE_AUTH, .SQLITE_PERM, .SQLITE_READONLY:
            return .permissionDenied(reason: permissionDeniedReason)
        case .SQLITE_CORRUPT, .SQLITE_NOTADB:
            return .schemaMismatch(detail: corruptReason)
        case .SQLITE_BUSY, .SQLITE_LOCKED:
            return .temporarilyUnavailable(reason: busyReason)
        default:
            return .permissionDenied(reason: permissionDeniedReason)
        }
    }

    private static let corruptReason = String(
        localized: "The TCC database appears to be unreadable or corrupt."
    )

    private static let busyReason = String(
        localized: "The TCC database is temporarily locked by macOS. Try Refresh in a moment."
    )
```

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsScanners --filter ScannerErrorMappingTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 6: Handle the new case in `PermissionsEmptyStateView` (compile fix)**

In `PermissionsEmptyStateView.swift`, the `switch error` is exhaustive and will not compile until the new case is handled. Replace the switch:

```swift
    var body: some View {
        switch error {
        case .permissionDenied:
            permissionDeniedView
        case .schemaMismatch, .unsupportedOnThisOS:
            schemaMismatchView
        case .temporarilyUnavailable:
            temporarilyUnavailableView
        case nil:
            emptyView
        }
    }
```

Add this computed view (place it after `schemaMismatchView`):

```swift
    private var temporarilyUnavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(String(localized: "Temporarily unavailable"))
                .font(.headline)
            Text(String(localized: "The database is busy right now. Use Refresh to try again."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
```

- [ ] **Step 7: Build the UI package to confirm exhaustiveness is satisfied**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -20`
Expected: Build succeeds (no "switch must be exhaustive" error). `SchemaMismatchBanner`, `DetailWindowView.isSchemaIssue`, and the `MenuBarContentView` helpers already use `default:`/`if case`, so no change is needed there.

- [ ] **Step 8: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift Packages/PermissionsScanners/Tests/PermissionsScannersTests/ScannerErrorMappingTests.swift Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift
git commit -m "fix(tcc): map SQLite error codes to accurate advice; add temporarilyUnavailable (C5)"
```

---

## Task 3: C7 — Stale-apps copy reflects the configured threshold

**Problem:** Two views hardcode "haven't used in 90+ days" but the threshold is user-configurable (30–365) since v0.7.0.

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift:21`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift:548,564`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelStaleThresholdTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelStaleThresholdTests.swift`:

```swift
import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelStaleThresholdTests {
    @Test func staleThresholdDaysDefaultsTo90() {
        #expect(AppViewModel().staleThresholdDays == 90)
    }

    @Test func staleThresholdDaysIsSettable() {
        let vm = AppViewModel()
        vm.staleThresholdDays = 30
        #expect(vm.staleThresholdDays == 30)
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelStaleThresholdTests 2>&1 | tail -20`
Expected: FAIL to compile — `AppViewModel` has no `staleThresholdDays` member.

- [ ] **Step 3: Add `staleThresholdDays` to `AppViewModel`**

In `AppViewModel.swift`, add the stored property after `scanInProgress` (line 50):

```swift
    // Mirror of the user's configured stale threshold, set by AppDelegate from
    // PreferencesStore so views can render the real number instead of "90+". (C7)
    public var staleThresholdDays: Int = 90
```

Add the matching `init` parameter (after `pendingDetailMode: DetailMode? = nil`):

```swift
        pendingDetailMode: DetailMode? = nil,
        staleThresholdDays: Int = 90
```

and the assignment in the `init` body (after `self.pendingDetailMode = pendingDetailMode`):

```swift
        self.staleThresholdDays = staleThresholdDays
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelStaleThresholdTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Interpolate the threshold in both views**

In `StaleAppsTabView.swift`, add a parameter and use it. Change the struct's stored properties (top of `StaleAppsTabView`):

```swift
struct StaleAppsTabView: View {
    let staleApps: [StaleApp]
    var staleThresholdDays: Int = 90
    @Environment(DismissedStaleAppStore.self) private var dismissedStore
```

Replace line 21's `Text(...)`:

```swift
                Text(String(localized: "Apps with active grants you haven't used in \(staleThresholdDays)+ days"))
```

In `DetailWindowView.swift`, update `StaleAppsDetailPage` to pass and render the threshold. Replace the `StaleAppsTabView(...)` call (line 548):

```swift
                StaleAppsTabView(staleApps: filteredApps, staleThresholdDays: viewModel.staleThresholdDays)
```

and the `subtitle` (line 564):

```swift
        return String(localized: "Apps with active grants you haven't used in \(viewModel.staleThresholdDays)+ days")
```

- [ ] **Step 6: Wire the value from PreferencesStore in the app**

In `PermissionPulseApp.swift`, in `applicationDidFinishLaunching`, set the value right after `coordinator = ScanCoordinator(viewModel: viewModel)` (line 140):

```swift
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
```

and add the same line inside `rescan()` after `viewModel.scanInProgress = true` (so a changed slider is reflected on the next scan, consistent with how the retention/threshold already take effect next cycle):

```swift
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
```

- [ ] **Step 7: Build and manually verify**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -5`
Expected: Build succeeds.
Manual: Run the app, open Preferences → Snapshots, set the stale threshold to 30, trigger a Refresh, open the detail window → Stale Apps. The subtitle reads "…haven't used in 30+ days."

- [ ] **Step 8: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift PermissionPulse/PermissionPulse/PermissionPulseApp.swift Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelStaleThresholdTests.swift
git commit -m "fix(ui): stale-apps copy reflects configured threshold, not hardcoded 90 (C7)"
```

---

## Task 4: C3 — Surface Launch Agent scan errors

**Problem:** `LaunchAgentScannerFS` swallows directory-read failures and returns `[]`; `ScanCoordinator` has no error field for launch agents; a failed scan is indistinguishable from "no launch agents."

**Files:**
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/LaunchAgentScannerFS.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `PermissionPulse/PermissionPulse/ScanCoordinator.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift`
- Test: `PermissionPulse/PermissionPulseTests/ScanCoordinatorTests.swift` (new)

- [ ] **Step 1: Add `launchAgentScanError` to `AppViewModel`**

In `AppViewModel.swift`, add after `btmScanError`:

```swift
    public var launchAgentScanError: ScannerError?
```

Add the `init` parameter (after `btmScanError: ScannerError? = nil`):

```swift
        btmScanError: ScannerError? = nil,
        launchAgentScanError: ScannerError? = nil,
```

and the assignment (after `self.btmScanError = btmScanError`):

```swift
        self.launchAgentScanError = launchAgentScanError
```

- [ ] **Step 2: Write the failing test**

Create `PermissionPulse/PermissionPulseTests/ScanCoordinatorTests.swift`:

```swift
import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ScanCoordinatorTests {
    private struct ThrowingLaunchAgentScanner: LaunchAgentScanner {
        func scan() async throws -> [LaunchAgentItem] {
            throw ScannerError.permissionDenied(reason: "boom")
        }
    }

    @Test func launchAgentScanErrorSurfacedToViewModel() async throws {
        let vm = AppViewModel()
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: MockTCCScanner(),
            launchAgentScanner: ThrowingLaunchAgentScanner(),
            btmScanner: MockBTMScanner()
        )
        await coordinator.runScan()
        guard case .permissionDenied(let reason)? = vm.launchAgentScanError else {
            Issue.record("Expected launchAgentScanError to be set"); return
        }
        #expect(reason == "boom")
    }

    @Test func launchAgentScanErrorClearedOnSuccess() async throws {
        let vm = AppViewModel(launchAgentScanError: .permissionDenied(reason: "stale"))
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: MockTCCScanner(),
            launchAgentScanner: MockLaunchAgentScanner(),
            btmScanner: MockBTMScanner()
        )
        await coordinator.runScan()
        #expect(vm.launchAgentScanError == nil)
        #expect(!vm.launchAgents.isEmpty)
    }
}
```

- [ ] **Step 3: Run the test to verify it FAILS**

Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/ScanCoordinatorTests 2>&1 | tail -20`
Expected: FAIL — `launchAgentScanError` is never set (the result struct has no error field).

- [ ] **Step 4: Add the error field and wire it in `ScanCoordinator`**

In `ScanCoordinator.swift`, replace the `LaunchAgentScanResult` struct, `runLaunchAgentScan`, and `applyLaunchAgents`:

```swift
    private struct LaunchAgentScanResult: Sendable {
        let items: [LaunchAgentItem]
        let error: ScannerError?
    }
```

```swift
    private func runLaunchAgentScan() async -> LaunchAgentScanResult {
        do {
            let items = try await launchAgentScanner.scan()
            return LaunchAgentScanResult(items: items, error: nil)
        } catch let scannerError as ScannerError {
            Self.logger.error("LaunchAgent scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return LaunchAgentScanResult(items: [], error: scannerError)
        } catch {
            Self.logger.error("LaunchAgent scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return LaunchAgentScanResult(items: [], error: .permissionDenied(reason: error.localizedDescription))
        }
    }
```

```swift
    private func applyLaunchAgents(_ result: LaunchAgentScanResult) {
        if let error = result.error {
            viewModel.launchAgentScanError = error
        } else {
            viewModel.launchAgents = result.items
            viewModel.launchAgentsDataSource = launchAgentsDataSource
            viewModel.launchAgentScanError = nil
        }
    }
```

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/ScanCoordinatorTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 6: Make `LaunchAgentScannerFS` actually propagate directory-read failures**

In `LaunchAgentScannerFS.swift`, the scanner currently can never throw. Make a directory that *exists but is unreadable* a real failure, while a *missing* directory stays a silent skip. Replace `scan()` and `scanDirectory(_:)`:

```swift
    public func scan() async throws -> [LaunchAgentItem] {
        var items: [LaunchAgentItem] = []
        var firstFailure: (any Error)?
        var anyReadable = false
        for source in sources {
            do {
                items.append(contentsOf: try scanDirectory(source))
                anyReadable = true
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        // Only surface an error if NO source was readable — a partial result
        // is still useful (under-flag, never over-flag).
        if !anyReadable, let firstFailure {
            throw firstFailure
        }
        return items.sorted {
            if $0.sourceDirectory.rawValue == $1.sourceDirectory.rawValue {
                return $0.label < $1.label
            }
            return $0.sourceDirectory.rawValue < $1.sourceDirectory.rawValue
        }
    }
```

```swift
    private func scanDirectory(_ source: Source) throws -> [LaunchAgentItem] {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: source.url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // A directory that doesn't exist is normal (not every Mac has all
            // three). A directory that exists but can't be enumerated is a real
            // failure worth surfacing. (C3)
            if fm.fileExists(atPath: source.url.path(percentEncoded: false)) {
                Self.logger.error("LaunchAgent directory unreadable \(source.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ScannerError.permissionDenied(
                    reason: String(localized: "A LaunchAgents directory could not be read.")
                )
            }
            Self.logger.debug("LaunchAgent directory absent \(source.url.path, privacy: .public)")
            return []
        }

        var items: [LaunchAgentItem] = []
        for fileURL in contents where fileURL.pathExtension.lowercased() == "plist" {
            if let item = decodePlist(at: fileURL, category: source.category) {
                items.append(item)
            }
        }
        return items
    }
```

(`import PermissionsCore` is already present, so `ScannerError` resolves.)

- [ ] **Step 7: Surface the error on the Launch Agents detail page**

In `DetailWindowView.swift`, find `LaunchAgentsDetailPage` (around line 431, with `@Environment(AppViewModel.self) private var viewModel` and `let searchText: String`). It currently renders the launch-agents list directly. Add an error branch at the very top of its `body`'s content, mirroring the established `tccScanError` pattern used by `PermissionsDetailPage` (line 393). Inside `LaunchAgentsDetailPage.body`, wrap the existing content so the error takes precedence:

```swift
        DetailPageScaffold(title: String(localized: "Launch Agents"), subtitle: nil) {
            if let error = viewModel.launchAgentScanError {
                PermissionsEmptyStateView(error: error, domain: .tcc)
            } else {
                // ... existing launch-agents list content unchanged ...
            }
        }
```

> Note: if `LaunchAgentsDetailPage` does not already use `DetailPageScaffold`, place the `if let error = viewModel.launchAgentScanError { PermissionsEmptyStateView(error: error, domain: .tcc) } else { <existing body> }` guard around its existing top-level content instead. The goal is: when `launchAgentScanError != nil`, the page shows the error state, not "no launch agents."

- [ ] **Step 8: Build and verify package + app**

Run: `swift test --package-path Packages/PermissionsScanners --filter LaunchAgentScannerFSTests 2>&1 | tail -20`
Expected: PASS — existing launch-agent scanner tests still pass (a non-existent fixture directory still returns `[]` without throwing).
Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -5`
Expected: Build succeeds.
Manual: not easily reproducible (LaunchAgents dirs are world-readable); the unit test covers the surfacing path.

- [ ] **Step 9: Commit**

```bash
git add Packages/PermissionsScanners/Sources/PermissionsScanners/LaunchAgentScannerFS.swift Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift PermissionPulse/PermissionPulse/ScanCoordinator.swift Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift PermissionPulse/PermissionPulseTests/ScanCoordinatorTests.swift
git commit -m "fix(scan): surface Launch Agent scan errors instead of empty list (C3)"
```

---

## Task 5: C2 — Distinguish "broken" from "empty"

**Problem:** A failed snapshot-store init or a failed diff query both render as the cheerful "come back tomorrow" empty state.

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:121-138`
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift:146-167`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAvailabilityTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAvailabilityTests.swift`:

```swift
import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelAvailabilityTests {
    @Test func availabilityFlagsDefaultFalse() {
        let vm = AppViewModel()
        #expect(vm.snapshotStoreUnavailable == false)
        #expect(vm.diffUnavailable == false)
    }

    @Test func availabilityFlagsAreSettable() {
        let vm = AppViewModel()
        vm.snapshotStoreUnavailable = true
        vm.diffUnavailable = true
        #expect(vm.snapshotStoreUnavailable)
        #expect(vm.diffUnavailable)
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelAvailabilityTests 2>&1 | tail -20`
Expected: FAIL to compile — the flags don't exist.

- [ ] **Step 3: Add the availability flags to `AppViewModel`**

In `AppViewModel.swift`, add after `staleThresholdDays` (from Task 3):

```swift
    // True when the snapshot store could not be opened — diff/stale history is
    // unavailable, which is NOT the same as "no changes yet." (C2)
    public var snapshotStoreUnavailable: Bool = false
    // True when a diff query errored (vs. genuinely having no prior snapshot). (C2)
    public var diffUnavailable: Bool = false
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelAvailabilityTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Set `snapshotStoreUnavailable` when the store fails to open**

In `PermissionPulseApp.swift`, in `applicationDidFinishLaunching`, replace the store-init block:

```swift
        do {
            let url = try SnapshotPath.canonicalURL()
            snapshotStore = try SnapshotStore(path: url.path(percentEncoded: false))
        } catch {
            Self.logger.error(
                "SnapshotStore init failed: \(error.localizedDescription, privacy: .public)"
            )
            viewModel.snapshotStoreUnavailable = true
        }
```

- [ ] **Step 6: Distinguish diff error from no-prior-snapshot in `SnapshotCoordinator`**

In `SnapshotCoordinator.swift`, `computeDiffs` currently returns `nil` for both "no prior snapshot" and "query failed." Set `diffUnavailable` only in the error path. Replace `computeDiffs`:

```swift
    private func computeDiffs(cutoff: Date, latestID: SnapshotID) async -> SnapshotDiffs? {
        do {
            guard let fromID = try await store.latestSnapshotID(atOrBefore: cutoff),
                  fromID != latestID else {
                return nil
            }
            async let tccTask = store.diffTCCGrants(from: fromID, to: latestID)
            async let btmTask = store.diffBTMItems(from: fromID, to: latestID)
            async let laTask  = store.diffLaunchAgents(from: fromID, to: latestID)
            let (tcc, btm, la) = try await (tccTask, btmTask, laTask)
            return SnapshotDiffs(
                fromID: fromID,
                toID: latestID,
                tcc: tcc,
                btm: btm,
                launchAgents: la
            )
        } catch {
            Self.logger.error("Diff query failed: \(error.localizedDescription, privacy: .public)")
            viewModel.diffUnavailable = true   // (C2) error, not "no data yet"
            return nil
        }
    }
```

Reset the flag at the start of a refresh so a recovered query clears it. In `refreshDiffsAndStale`, add right after `viewModel.latestSnapshotID = latestID` (line 120):

```swift
        viewModel.diffUnavailable = false
```

- [ ] **Step 7: Render the error states in `DiffTabView`**

In `DiffTabView.swift`, the view takes `diff: SnapshotDiffs?`. Add the two new flags as parameters and branch on them before the existing logic. Change the stored properties:

```swift
struct DiffTabView: View {
    let diff: SnapshotDiffs?
    let windowLabel: DiffWindowLabel
    var snapshotStoreUnavailable: Bool = false
    var diffUnavailable: Bool = false
    @Environment(DismissedDiffEntryStore.self) private var dismissedStore
```

At the top of `body`, before `if let diff {`:

```swift
    var body: some View {
        let now = Date()

        if snapshotStoreUnavailable {
            unavailableState(
                headline: String(localized: "Snapshot history unavailable"),
                detail: String(localized: "Permission Pulse couldn't open its local database, so it can't track changes. Try Reset All Data in Preferences.")
            )
        } else if diffUnavailable {
            unavailableState(
                headline: String(localized: "Couldn't read changes"),
                detail: String(localized: "A problem reading the local database prevented computing changes. Try Refresh.")
            )
        } else if let diff {
            // ... existing `if let diff` body unchanged ...
        } else {
            emptyNoPriorState
        }
    }
```

Add the shared error view (after `emptyContentState`):

```swift
    private func unavailableState(headline: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(headline).font(.headline)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
```

Update the call site of `DiffTabView` in `DetailWindowView.swift` (the Recent Changes page) to pass the flags — find the `DiffTabView(diff:` construction and add the two arguments:

```swift
            DiffTabView(
                diff: <existing diff argument>,
                windowLabel: <existing windowLabel argument>,
                snapshotStoreUnavailable: viewModel.snapshotStoreUnavailable,
                diffUnavailable: viewModel.diffUnavailable
            )
```

- [ ] **Step 8: Build and verify**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -5`
Expected: Build succeeds.
Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelAvailabilityTests 2>&1 | tail -10`
Expected: PASS.
Manual: temporarily make `SnapshotPath.canonicalURL()` return a path inside a non-writable directory (or chmod the Application Support dir) to confirm the "Snapshot history unavailable" state appears instead of "come back tomorrow." Revert after.

- [ ] **Step 9: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift PermissionPulse/PermissionPulse/PermissionPulseApp.swift PermissionPulse/PermissionPulse/SnapshotCoordinator.swift Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAvailabilityTests.swift
git commit -m "fix(ui): distinguish broken store/diff from empty state (C2)"
```

---

## Task 6: C4 — Reset gives feedback and never leaves a dangling store

**Problem:** `performReset` silently returns if the path lookup fails; `ResetAllDataService` logs but doesn't surface a re-init failure, leaving the coordinator pointing at a deleted DB.

**Files:**
- Modify: `PermissionPulse/PermissionPulse/ResetAllDataService.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:196-221`
- Test: `PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift`

- [ ] **Step 1: Add a `reinitFailed` outcome to `ResetAllDataService`**

In `ResetAllDataService.swift`, make `reset()` report whether store re-init succeeded so the caller can react. Change the signature to return a `Bool` and set it in the catch. Replace the re-init block inside `reset()`:

```swift
        // 3. Re-init the snapshot store at the same path so subsequent
        //    scans have somewhere to write.
        var reinitSucceeded = false
        do {
            let newStore = try SnapshotStore(path: snapshotPathURL.path(percentEncoded: false))
            onSnapshotStoreReinit(newStore)
            reinitSucceeded = true
        } catch {
            Self.logger.error(
                "Failed to re-init snapshot store after reset: \(error.localizedDescription, privacy: .public)"
            )
        }
```

Change `func reset() async {` to `func reset() async -> Bool {` and add `return reinitSucceeded` as the final line (after the `await rescan()` step). Update the doc comment's first line to note it returns whether re-init succeeded.

- [ ] **Step 2: Write the failing test**

In `ResetAllDataServiceTests.swift`, add a test that a normal reset reports success. (The existing suite already constructs a service; mirror its `Environment`/setup — this test asserts the new return value.)

```swift
    @Test func resetReportsReinitSuccess() async throws {
        let env = try await Environment()
        let succeeded = await env.service.reset()
        #expect(succeeded == true)
    }
```

> If the existing `ResetAllDataServiceTests` uses a different helper name than `Environment`/`service`, mirror that file's existing setup exactly — the assertion is `#expect(await <service>.reset() == true)`.

- [ ] **Step 3: Run the test to verify it FAILS**

Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/ResetAllDataServiceTests 2>&1 | tail -20`
Expected: FAIL to compile — `reset()` returns `Void`, not `Bool` (until Step 1 is applied), or the value isn't returned. Once Step 1 is applied this test passes; if you wrote the test before Step 1, it fails to compile first (true RED).

- [ ] **Step 4: Confirm Step 1 satisfies it, then handle the result + path failure in the app**

In `PermissionPulseApp.swift`, replace `performReset()`:

```swift
    private func performReset() async {
        let url: URL
        do {
            url = try SnapshotPath.canonicalURL()
        } catch {
            Self.logger.error("Reset aborted — cannot resolve data path: \(error.localizedDescription, privacy: .public)")
            presentResetError(
                message: String(localized: "Reset failed: Permission Pulse couldn't locate its data folder.")
            )
            return
        }
        let service = ResetAllDataService(
            viewModel: viewModel,
            snapshotPathURL: url,
            onSnapshotStoreReinit: { [weak self] newStore in
                self?.snapshotStore = newStore
                if let self {
                    self.snapshotCoordinator = SnapshotCoordinator(
                        viewModel: self.viewModel,
                        store: newStore,
                        snapshotRetentionDays: self.preferencesStore.snapshotRetentionDays,
                        staleThresholdDays: self.preferencesStore.staleThresholdDays,
                        dismissedStaleApps: self.dismissedStaleApps
                    )
                }
            },
            weeklyDigestCoordinator: weeklyDigestCoordinator,
            defaults: .standard,
            rescan: { [weak self] in
                await self?.rescan()
                await self?.weeklyDigestCoordinator.reconcileSchedule()
            }
        )
        let reinitSucceeded = await service.reset()
        if !reinitSucceeded {
            // Don't let scans write to a store we couldn't recreate.
            snapshotCoordinator = nil
            viewModel.snapshotStoreUnavailable = true
            presentResetError(
                message: String(localized: "Data was cleared, but Permission Pulse couldn't recreate its database. Restart the app to recover.")
            )
        }
    }

    private func presentResetError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset Permission Pulse")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
```

(`viewModel.snapshotStoreUnavailable` comes from Task 5 — Task 6 depends on Task 5.)

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/ResetAllDataServiceTests 2>&1 | tail -20`
Expected: PASS (existing tests + the new `resetReportsReinitSuccess`).

- [ ] **Step 6: Manual verification**

Manual: trigger Reset All Data from Preferences on a normal run — confirm it still completes silently (no error alert) and the UI repopulates. The failure-path alert is covered by inspection (forcing a re-init failure requires deleting the Application Support directory mid-reset).

- [ ] **Step 7: Commit**

```bash
git add PermissionPulse/PermissionPulse/ResetAllDataService.swift PermissionPulse/PermissionPulse/PermissionPulseApp.swift PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift
git commit -m "fix(reset): surface reset failures and guard against dangling store (C4)"
```

---

## Task 7: C6 — Reduce mic/cam false-negatives

**Problem:** `MediaUseObserverCMIO` only queries devices whose property listener registered successfully. If registration fails, that device is never polled, so the menu-bar dot can report "not in use" while the camera is live.

**Scope note:** The live CoreMediaIO/CoreAudio path cannot be unit-tested (it talks to hardware), consistent with the rest of the live-scanner layer. This task makes the **initial and aggregate reads poll every enumerated device** (not just registered ones), which is the core false-negative reduction, and logs when listeners are incomplete. A visible "monitoring degraded" UI indicator is deferred to the Thread B / UX work.

**Files:**
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/MediaUseObserverCMIO.swift`

- [ ] **Step 1: Retain all enumerated device IDs separately from the registered listeners**

In `MediaUseObserverCMIO.swift`, add two stored arrays next to the listener arrays (after line 21):

```swift
    private var allVideoDeviceIDs: [CMIOObjectID] = []
    private var allAudioDeviceIDs: [AudioObjectID] = []
```

In `startObservingVideo()`, capture the enumerated IDs before the registration loop. Replace its first line:

```swift
    private func startObservingVideo() {
        let ids = enumerateVideoDevices()
        lock.withLock { allVideoDeviceIDs = ids }
```

In `startObservingAudio()`, replace its first line:

```swift
    private func startObservingAudio() {
        let ids = enumerateAudioInputDevices()
        lock.withLock { allAudioDeviceIDs = ids }
```

- [ ] **Step 2: Poll all enumerated devices in the initial and aggregate reads**

In `emitInitialState()`, replace the two `lock.withLock { ...Listeners.map(\.id) }` reads with the full device lists:

```swift
    private func emitInitialState() {
        let videoIDs = lock.withLock { allVideoDeviceIDs }
        let audioIDs = lock.withLock { allAudioDeviceIDs }

        let cameraInUse = videoIDs.contains { queryVideoIsRunning($0) }
        let micInUse = audioIDs.contains { queryAudioIsRunning($0) }

        emit(MediaUseEvent(device: .camera, inUse: cameraInUse, timestamp: Date()))
        emit(MediaUseEvent(device: .microphone, inUse: micInUse, timestamp: Date()))
    }
```

In `handleDeviceChange(_:isRunning:)`, replace the two `lock.withLock { ...Listeners.map(\.id) }` reads:

```swift
        case .camera:
            let ids = lock.withLock { allVideoDeviceIDs }
            aggregate = isRunning || ids.contains { queryVideoIsRunning($0) }
        case .microphone:
            let ids = lock.withLock { allAudioDeviceIDs }
            aggregate = isRunning || ids.contains { queryAudioIsRunning($0) }
```

- [ ] **Step 3: Log when listener registration is incomplete**

At the end of `events()`, after `self.emitInitialState()`, add a degraded-monitoring log:

```swift
            self.emitInitialState()

            let (vAll, vReg, aAll, aReg) = self.lock.withLock {
                (self.allVideoDeviceIDs.count, self.videoListeners.count,
                 self.allAudioDeviceIDs.count, self.audioListeners.count)
            }
            if vReg < vAll || aReg < aAll {
                Self.logger.error("Media monitoring degraded — live updates may be missed (video \(vReg)/\(vAll), audio \(aReg)/\(aAll))")
            }
```

Also clear the device lists in `tearDownListeners()` — add inside the `lock.withLock` block that empties the listener arrays (after `audioListeners.removeAll()`):

```swift
            allVideoDeviceIDs.removeAll()
            allAudioDeviceIDs.removeAll()
```

- [ ] **Step 4: Build and verify**

Run: `swift build --package-path Packages/PermissionsScanners 2>&1 | tail -5`
Expected: Build succeeds.
Run: `swift test --package-path Packages/PermissionsScanners --filter MockMediaUseObserverTests 2>&1 | tail -10`
Expected: PASS (the mock-observer tests are unaffected).
Manual: open Photo Booth (camera) and a recording app (mic); confirm the menu-bar dot reflects both. With the change, the initial state is polled across all enumerated devices even if a listener failed to attach.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsScanners/Sources/PermissionsScanners/MediaUseObserverCMIO.swift
git commit -m "fix(media): poll all enumerated devices to cut mic/cam false-negatives (C6)"
```

---

## Final verification (after all tasks)

- [ ] **Run every package test suite**

```bash
swift test --package-path Packages/PermissionsCore 2>&1 | tail -5
swift test --package-path Packages/PermissionsScanners 2>&1 | tail -5
swift test --package-path Packages/PermissionsStore 2>&1 | tail -5
swift test --package-path Packages/PermissionsUI 2>&1 | tail -5
```
Expected: all green; counts at or above the prior ~161 (Core 15, Scanners 48+, Store 24, UI 74+).

- [ ] **Run the app-target tests**

```bash
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests 2>&1 | tail -20
```
Expected: TEST SUCCEEDED — `SnapshotCoordinatorTests` (+1), `ScanCoordinatorTests` (new, 2), `ResetAllDataServiceTests` (+1), `WeeklyDigestCoordinatorTests` unchanged.

- [ ] **Run the full smoke test**

```bash
./scripts/smoke-test.sh --no-launch
```
Expected: §1–§5 pass. Then manually walk the relevant checklist items (Stale Apps threshold copy, Recent Changes states).

---

## Self-Review (completed during planning)

**Spec coverage:** C1→Task 1, C2→Task 5, C3→Task 4, C4→Task 6, C5→Task 2, C6→Task 7, C7→Task 3. All seven P0 items covered.

**Dependencies:** Task 6 (C4) depends on Task 5 (C2) for `viewModel.snapshotStoreUnavailable`. Task 3 (C7) and Task 5 (C2) both add `AppViewModel` members and `PermissionPulseApp` wiring — apply in order (3 before 5) to avoid edit conflicts in those two files. All other tasks are independent.

**Type consistency:** `staleThresholdDays`, `launchAgentScanError`, `snapshotStoreUnavailable`, `diffUnavailable` are defined once on `AppViewModel` and referenced consistently. `ScannerError.temporarilyUnavailable(reason:)` is added in Task 2 and only matched in `PermissionsEmptyStateView` (other sites use `default:`/`if case`). `ResetAllDataService.reset()` becomes `-> Bool` (Task 6) — the only caller is `performReset`, updated in the same task.

**Testability honesty:** C1, C5, C7, C3, C2-flags, C4-return are unit-tested. SwiftUI view rendering (C2/C3 states), the reset failure alert (C4), and the live media path (C6) are build + manual, matching the codebase's existing test strategy (views/live scanners are not unit-tested; view models and mocks are).
