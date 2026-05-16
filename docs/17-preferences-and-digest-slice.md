# 17 — Eighth slice: preferences pane and weekly digest

**Status:** Implemented v0.7.0 — 2026-05-16.

## Why this slice

- v0.6.0 closed the per-row "what does this grant mean?" gap and put a one-click revoke path within reach of every Permissions row. The product can now answer "what is granted?", "what changed?", "which apps are stale?", and "what does this grant let the app do?" — but it cannot remember the user's *preferences* about any of them. Snapshot retention, the stale threshold, and the (still hypothetical) digest cadence were hardcoded constants in `SnapshotCoordinator`. Dismissals from Recent Changes / Stale Apps didn't persist either, so every reopen re-surfaced the same items the user had already mentally checked off. v0.7.0 fixes both gaps.
- It also closes the recurrence loop. Until v0.7.0, the user had to *open* Permission Pulse to discover changes; the bell-badge icon flipped on after a scan but nothing pulled the user back. A weekly opt-in local notification turns the daily snapshot from passive memory into active hygiene. Paired with per-row dismissals (so the user can quiet noise without losing signal), the slice converts v0.5.0/v0.6.0 from a viewer into a workflow.

## Scope cut

- **In v0.7.0:** A. Preferences pane · B. Weekly local notification · C. Per-row dismiss/snooze on Recent Changes · D. Skip-stale-app-forever.
- **Deferred:** E (sub-service preservation) bundles with H (`auth_value`) in a future "model fidelity" slice. F (Sonoma/Sequoia anchor verification) needs a VM matrix. G (BTM tree view) is cosmetic. Notification click → Recent Changes routing is v0.7.1.

## What shipped

1. **`PreferencesStore`** in `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift`. `@Observable @MainActor` wrapper over `UserDefaults` for the six new keys (snapshot retention, stale threshold, digest enabled/weekday/hour/minute). Public static keys at the top so call sites and tests share one source of truth. Clamps on read AND write to safe ranges so a corrupted blob cannot push the rest of the app off a cliff. Includes a `digestTime() / setDigestTime(_:)` convenience pair for the `.hourAndMinute` `DatePicker` binding.

2. **Retention + stale threshold flow through `SnapshotCoordinator`.** The two `static let` constants were replaced with init-injected `let` properties (`snapshotRetentionDays`, `staleThresholdDays`); defaults preserve v0.6.0 behavior. `AppDelegate` reads the values from `preferencesStore` at construction. New values take effect on the next scan cycle — no live re-prune mid-session; comment in source explains why (avoids surprise data deletion when the user drags a slider).

3. **`WeeklyDigestScheduler` protocol** in `Packages/PermissionsCore/Sources/PermissionsCore/WeeklyDigestScheduler.swift`. Surface: `currentAuthorizationStatus()`, `requestAuthorization()`, `scheduleWeekly(...)`, `cancelAll(matchingPrefix:)`, `pendingIdentifiers()`. A `DigestAuthorizationStatus` mirror enum keeps callers from having to import `UserNotifications`. **`LiveWeeklyDigestScheduler`** wraps `UNUserNotificationCenter.current()` and lives in `PermissionsScanners` (same package as the other live system-API integrations: `TCCScannerSQLite`, `BTMScannerDirect`, `MediaUseObserverCMIO`, `LastUsedProbeHybrid`). **`MockWeeklyDigestScheduler`** is an actor with an event log of `(action, identifier, params)` tuples and configurable authorization status.

4. **`WeeklyDigestCoordinator`** in `PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift`. `@MainActor final class`, sibling of `SnapshotCoordinator`. Three responsibilities:
   - `reconcileSchedule() async` — cancel-then-schedule under one stable identifier prefix (`com.wallymagill.permissionpulse.digest.weekly`); composes title/body from `viewModel.latestDiffWeek`; idempotent on re-call.
   - `handleAuthorizationToggle(turnOn:) async -> AuthorizationResult` — returns `.scheduled` / `.deniedNeedsSystemSettings` / `.disabled` so the Preferences UI can pick the right hint. Prompts at first opt-in (`.notDetermined`) via `requestAuthorization`.
   - `composeDigestBody(diff:)` — pure, easily tested. All strings via `String(localized:)`. Empty-week ships "No changes in the last week." (heartbeat, not silence — silence would be misread).

5. **`PreferencesViewModel` + `PreferencesWindowView`.** `TabView` with two tabs.
   - *Snapshots:* retention slider (7–365), stale threshold slider (30–365), Reset All Data… button (destructive, disables while a scan is mid-flight with an inline orange hint).
   - *Notifications:* weekly digest toggle wired through `WeeklyDigestCoordinator.handleAuthorizationToggle`; weekday `Picker` (Sunday → Saturday); `.hourAndMinute` `DatePicker`; three-state hint label (not-yet-asked / scheduled / denied-with-deep-link to System Settings).
   - Opened via `WindowGroup(id: "preferences")` declared *after* the trampoline and *before* the detail window — sidesteps the Tahoe `MenuBarExtra` + `Settings` scene regression by reusing the proven `WindowGroup` + `openWindow(id:)` pattern.
   - New ⌘, menu entry in `MenuBarContentView` (between "Open Permission Pulse" and Quit).

6. **`DismissedDiffEntryStore` + `DiffEntryKey`** in `Packages/PermissionsUI/Sources/PermissionsUI/`. JSON `[String: Date]` map persisted under `com.wallymagill.permissionpulse.dismissedDiffEntries`; keys map to expiry timestamps (`.distantFuture` = forever, anything else = snooze). Defensive decode falls back to empty map on corruption. `DiffEntryKey` is a pure mapper from `ChangeRow.Kind` to a stable semantic key that omits snapshot ID so a dismissal carries across snapshots (e.g. `tcc-granted|<service>|<bundleID>|<automationTarget>`). `DiffTabView` filters by `isDismissed(key:, asOf: now)` and offers a trailing ellipsis `Menu` per row with "Dismiss" / "Snooze 7 days".

7. **`DismissedStaleAppStore`** in `Packages/PermissionsUI/Sources/PermissionsUI/`. Simpler shape: `Set<String>` of bundleIDs persisted as a `[String]` UserDefaults array under `com.wallymagill.permissionpulse.dismissedStaleApps`. `SnapshotCoordinator.computeStaleApps` filters dismissed bundleIDs so the sidebar badge count stays honest end-to-end. `StaleAppsTabView` additionally applies a view-side filter for immediate post-click feedback and offers a trailing ellipsis `Menu` → "Skip forever" with a destructive confirmation alert.

8. **`SystemSettingsLink.openNotifications()`** in `Packages/PermissionsUI/Sources/PermissionsUI/SystemSettingsLink.swift`. New `notificationsURL` (`x-apple.systempreferences:com.apple.preference.notifications`); same graceful-degradation pattern as the existing Privacy anchors.

9. **`ResetAllDataService` + `ResetConfirmationSheet`** in `PermissionPulse/PermissionPulse/ResetAllDataService.swift` and `Packages/PermissionsUI/Sources/PermissionsUI/ResetConfirmationSheet.swift`. Reset cascade:
   1. Cancel pending digest notifications (`scheduler.cancelAll(matchingPrefix:)`).
   2. Delete `snapshots.db` (`try?`).
   3. Re-init `SnapshotStore` at the same path; AppDelegate replaces its `snapshotCoordinator` via the `onSnapshotStoreReinit` callback.
   4. Remove every UserDefaults key prefixed with `com.wallymagill.permissionpulse.` — explicit prefix filter preserves `NSWindow`/`NSStatusItem`/`NSSplitView` keys macOS auto-writes under our bundle domain.
   5. Wipe in-memory ViewModel state (grants, launch agents, BTM items, diffs, stale apps, snapshot IDs).
   6. Trigger a fresh scan and `reconcileSchedule()`.
   - Idempotent — a second call with no DB and empty defaults completes the same way.
   - Welcome window is deliberately NOT re-shown this session; next cold launch will re-show because `hasSeenWelcome` is gone.
   - Confirmation sheet hosted via `NSWindow` (matches the Welcome window pattern, sidesteps SwiftUI sheet timing oddities for a one-shot dialog launched from another window).

10. **`AppViewModel.scanInProgress`** (new `Bool` in `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift`). `AppDelegate` brackets every scan (initial + `rescan()`) with `set true` / `set false`; Preferences uses it to disable the Reset button while a scan is in flight with an inline orange hint.

11. **`WeeklyDigestCoordinator.scheduler`** is `internal` (not `private`) so `ResetAllDataService` can cancel pending notifications without rebuilding the coordinator.

## Data flow

```
Boot
  AppDelegate.applicationDidFinishLaunching
    ├─ preferencesStore       = PreferencesStore(defaults: .standard)
    ├─ dismissedDiffEntries   = DismissedDiffEntryStore(defaults: .standard)
    ├─ dismissedStaleApps     = DismissedStaleAppStore(defaults: .standard)
    ├─ snapshotStore          = SnapshotStore(path: …)
    ├─ snapshotCoordinator    = SnapshotCoordinator(
    │     snapshotRetentionDays: preferencesStore.snapshotRetentionDays,
    │     staleThresholdDays:    preferencesStore.staleThresholdDays,
    │     dismissedStaleApps:    dismissedStaleApps,
    │     …)
    ├─ weeklyDigestCoordinator = WeeklyDigestCoordinator(
    │     scheduler: LiveWeeklyDigestScheduler(), …)
    └─ Task { viewModel.scanInProgress = true
              runScan → snapshotCoordinator.onScanCompleted
              viewModel.scanInProgress = false
              weeklyDigestCoordinator.reconcileSchedule }

User → Preferences → digest toggle ON
  PreferencesViewModel.handleDigestToggle(to: true)
    → WeeklyDigestCoordinator.handleAuthorizationToggle(turnOn: true)
        status == .notDetermined → requestAuthorization → granted/denied
        granted   → reconcileSchedule (cancelAll then scheduleWeekly)
        denied    → UI shows "Open Notifications…" (SystemSettingsLink.openNotifications)

User → Preferences → Reset All Data… → confirm
  ResetConfirmationSheet → ResetAllDataService.reset()
    1. weeklyDigestCoordinator.scheduler.cancelAll(matchingPrefix:)
    2. FileManager.removeItem(at: snapshots.db)
    3. re-init SnapshotStore at same path → AppDelegate replaces snapshotCoordinator
    4. defaults.dictionaryRepresentation().keys
         .filter { $0.hasPrefix("com.wallymagill.permissionpulse.") }
         .forEach { defaults.removeObject(forKey: $0) }
    5. viewModel reset (grants/launchAgents/btmItems/diffs/staleApps = empty)
    6. AppDelegate.rescan → snapshotCoordinator.onScanCompleted → weeklyDigestCoordinator.reconcileSchedule

Recent Changes render
  DiffTabView reads viewModel.latestDiffYesterday/Week
    for each ChangeRow.Kind:
       key = DiffEntryKey.key(for: kind)
       if dismissedDiffEntries.isDismissed(key:, asOf: now) → skip
       else render with trailing Menu:
            "Dismiss"      → dismissedDiffEntries.dismissForever(key:)
            "Snooze 7 days" → dismissedDiffEntries.snooze(key:, until: now + 7d)

Stale Apps render
  StaleAppsTabView reads viewModel.staleApps (already filtered by coordinator)
    trailing Menu:
       "Skip forever" → confirmation alert
                        → dismissedStaleApps.skipForever(bundleID:)
                        → row disappears (local filter) + next scan keeps it gone (coordinator)
```

## Files touched

### New
- `Packages/PermissionsCore/Sources/PermissionsCore/WeeklyDigestScheduler.swift`
- `Packages/PermissionsScanners/Sources/PermissionsScanners/LiveWeeklyDigestScheduler.swift`
- `Packages/PermissionsScanners/Sources/PermissionsScanners/MockWeeklyDigestScheduler.swift`
- `Packages/PermissionsScanners/Tests/PermissionsScannersTests/MockWeeklyDigestSchedulerTests.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesViewModel.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/DismissedDiffEntryStore.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/DismissedStaleAppStore.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift`
- `Packages/PermissionsUI/Sources/PermissionsUI/ResetConfirmationSheet.swift`
- `Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesStoreTests.swift`
- `Packages/PermissionsUI/Tests/PermissionsUITests/PreferencesViewModelTests.swift`
- `Packages/PermissionsUI/Tests/PermissionsUITests/DismissedDiffEntryStoreTests.swift`
- `Packages/PermissionsUI/Tests/PermissionsUITests/DismissedStaleAppStoreTests.swift`
- `Packages/PermissionsUI/Tests/PermissionsUITests/DiffEntryKeyTests.swift`
- `PermissionPulse/PermissionPulse/WeeklyDigestCoordinator.swift`
- `PermissionPulse/PermissionPulse/ResetAllDataService.swift`
- `PermissionPulse/PermissionPulseTests/WeeklyDigestCoordinatorTests.swift`
- `PermissionPulse/PermissionPulseTests/ResetAllDataServiceTests.swift`
- `docs/17-preferences-and-digest-slice.md` (this file)

### Modified
- `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` — `WindowGroup(id: "preferences")` after the trampoline; constructs five new owned objects; boot Task brackets scan with `scanInProgress`; calls `reconcileSchedule()` at end of boot; hosts reset confirmation NSWindow; injects `dismissedDiffEntries` / `dismissedStaleApps` into detail window environment.
- `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift` — replace `static let` thresholds with injected `let`; inject `dismissedStaleApps`; filter in `computeStaleApps`.
- `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` — add `scanInProgress: Bool`.
- `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` — `Preferences…` entry between "Open Permission Pulse" and Quit.
- `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift` — filter via `DismissedDiffEntryStore`; trailing `Menu` per row.
- `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift` — accept `onDismissForever` / `onSnooze` closures and render a trailing ellipsis `Menu` when either is provided.
- `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift` — accept `DismissedStaleAppStore` from environment; view-side filter; trailing `Menu` + confirmation alert.
- `Packages/PermissionsUI/Sources/PermissionsUI/SystemSettingsLink.swift` — `notificationsURL` + `openNotifications()`.
- `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift` — +3 cases (`customStaleThresholdHonored`, `customRetentionHonored`, `staleAppsFilteredByDismissedStaleAppsStore`); `Environment` accepts new injectable params.
- `PermissionPulse/PermissionPulse.xcodeproj/project.pbxproj` — `MARKETING_VERSION = 0.7.0`, `CURRENT_PROJECT_VERSION = 10` across all 6 occurrences.
- `docs/09-roadmap.md` — mark v0.7.0 done; reference this file.
- `docs/04-data-sources.md` — Preferences section (6 keys) + Weekly Digest section.
- `CLAUDE.md` — list the 6 new UserDefaults keys; add `UNUserNotificationCenter on unsigned bundles` row in "Known fragile surfaces".

## Test coverage

- `PreferencesStoreTests` — 7 cases.
- `PreferencesViewModelTests` — 4 cases.
- `DismissedDiffEntryStoreTests` — 5 cases.
- `DismissedStaleAppStoreTests` — 3 cases.
- `DiffEntryKeyTests` — 4 cases.
- `MockWeeklyDigestSchedulerTests` — 2 cases.
- `WeeklyDigestCoordinatorTests` — 7 cases.
- `ResetAllDataServiceTests` — 4 cases.
- `SnapshotCoordinatorTests` (extension) — 3 cases.

Per-package totals after rollup:
- `PermissionsCore`: 12 → 15 (no behavioral tests for the protocol; the +3 was post-v0.6.0 polish that came along).
- `PermissionsScanners`: 42 → 45 (+2 mock + 1 polish).
- `PermissionsUI`: 29-34 → 70 (large jump because the v0.6.x polish work added ~13 tests too).
- `PermissionsStore`: 22 unchanged.
- App target: 5 → 20 (+15: 3 SnapshotCoordinator extensions + 7 WeeklyDigestCoordinator + 4 ResetAllDataService + 1 pre-existing smoke).

Grand total: **172 tests** (was 129 → +43, comfortably above the +28 floor and +37 ceiling targets in the plan).

## Risks (mostly Tahoe-specific)

| # | Risk | Mitigation |
|---|---|---|
| 1 | **`UNUserNotificationCenter` may show a generic bundle label on an unsigned `.app`** — cosmetic but undermines trust. | Hand-test on Tahoe before shipping the release; if the label is wrong and unfixable without Developer ID, ship without B and defer to v0.7.1. Do NOT add entitlements. |
| 2 | **Tahoe `MenuBarExtra` + native `Settings` scene regression.** | Use `WindowGroup(id: "preferences")` declared after the trampoline + open via `openWindow(id:)`. Proven pattern (mirrors `detail`). |
| 3 | **Pending-notification leakage** if scheduler bugs queue multiple weekly fires. | Always cancel-then-schedule under one identifier prefix. `WeeklyDigestCoordinatorTests.reconcileScheduleCalledTwiceIsIdempotent` asserts `pendingIdentifiers().count == 1` after double reconcile. |
| 4 | **`UNAuthorizationStatus.denied` is silent** — toggling on won't re-prompt. | Coordinator returns `.deniedNeedsSystemSettings` explicitly; Preferences hint shows a permanent "Open Notifications…" link via `SystemSettingsLink.openNotifications()`. |
| 5 | **Reset-all-data while scan is in flight** — could race the snapshot writer. | `viewModel.scanInProgress` gates the Reset button; AppDelegate brackets every scan with set/unset. |
| 6 | **UserDefaults JSON corruption** on `DismissedDiffEntryStore`. | Defensive `try?` decode → empty map on nil + OSLog warning. Test `corruptDefaultsReadsAsEmptyAndNextWriteRecovers` pins behavior. |
| 7 | **Reset clobbers `hasSeenWelcome`** → Welcome window re-shows on next cold launch. | Deliberate: user invoked Reset; rehydrating from scratch makes sense. Same-session: no re-open (reset doesn't trigger Welcome). |
| 8 | **Dismissal keys break if a service rawValue or BTM identifier renames in future.** | Keys are computed from the same fields the diff engine uses — both sides invalidate together. Orphaned keys become harmless dead entries. |

## Deferred to later slices

- E. Sub-service preservation (Files/Folders, Photos, Bluetooth) — bundles with H in a future "model fidelity" slice (v0.8.x).
- F. Sonoma + Sequoia anchor verification — needs a VM matrix.
- G. BTM developer-group tree view — cosmetic, no user pressure.
- H. `auth_value` tracking for TCC — pairs with E.
- Notification click → open Recent Changes — needs `UNUserNotificationCenterDelegate` + routing into `pendingDetailMode`. v0.7.1.
- Global hotkey for Preferences (`KeyboardShortcuts` dep) — third-party dep; defer.

## Done means

- All five package suites + the app target test bundle pass — **172 tests total**.
- `xcodebuild -scheme PermissionPulse -configuration Release build` succeeds; resulting `.app` reports `CFBundleShortVersionString = 0.7.0` and `CFBundleVersion = 10`.
- Fresh launch on Tahoe:
  - Menu-bar dropdown shows three rows above Quit: "What Changed", "Open Permission Pulse", "Preferences…".
  - Clicking "Preferences…" opens a two-tab window. Snapshots tab shows retention slider at 90, stale threshold at 90, Reset All Data… (red, disabled while a scan is mid-flight). Notifications tab shows weekly digest toggle off, weekday picker = Monday, time picker = 9:00 AM, hint "Flip the toggle on to enable notifications. macOS will ask for permission."
- Flip digest toggle on → system prompt shows "Permission Pulse" → on grant, hint = "Weekly digest is on."; `pendingIdentifiers()` returns exactly one entry. On deny, hint = "Notifications are off in System Settings." with a working "Open Notifications…" link.
- Recent Changes: ellipsis menu per row → Dismiss / Snooze 7 days. Dismiss → row gone, persists across reopen. Snooze + clock advance 8 days → row returns.
- Stale Apps: ellipsis menu → Skip forever → confirm → row gone immediately; sidebar badge agrees.
- Snapshots tab: drag retention to 30 → close → next scan prunes to 30 days. Drag stale to 180 → next scan recomputes.
- Reset All Data… → confirm → `snapshots.db` removed and re-created empty; all `com.wallymagill.permissionpulse.*` defaults gone; pending notifications canceled; scan re-runs; Welcome window does NOT re-open in this session.
- All v0.5.0 / v0.6.0 surfaces unchanged.
