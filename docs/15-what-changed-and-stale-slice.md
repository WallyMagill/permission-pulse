# 15 — Sixth slice: snapshot store extension, "What Changed", and Stale App Review

**Status:** Implemented v0.5.0 — 2026-05-15.

## Why this slice

- v0.4.1 closed the live-state surface (mic/cam observer + state-driven menu-bar icon). The product so far answers "what is granted right now?" The recurrence question — "what changed since yesterday?", "what changed since last week?", "which TCC-granted apps haven't been used in months?" — needs persisted snapshots to answer.
- `SnapshotStore` was scaffolded in v0.2.0 with a `launch_agents` table at schema v2, but the production write path was never wired into `ScanCoordinator`. v0.5.0 wires it for all three domains, adds `tcc_grants` + `btm_items` tables in migration v3, surfaces diffs and stale apps in a new "What Changed" window, and adds a 6th menu-bar icon state for unreviewed changes.
- Stale App Review is a separately-named scope item but the natural home is the same window — it answers a forward-looking question ("which TCC-granted apps are stale?") in the same surface as the backward-looking diff ("what changed?"). One window with three tabs keeps the cost of opening Permission Pulse low: one place to scan, decide, close.

## Preconditions verified

- `mdls -name kMDItemLastUsedDate -raw <path>` was tested on four `.app` bundles on this machine. Three returned `(null)`; one returned a real ISO-style date. **Spotlight metadata is not reliable enough as a sole source.** The hybrid (Spotlight first, then `URL.contentModificationDateKey`, then skip the app) is mandatory.
- SF Symbols `bell.badge.fill` and `exclamationmark.bubble.fill` both resolve on Tahoe 26.1 via `NSImage(systemSymbolName:_:)` — verified before depending on the preferred name.
- GRDB v7.x `DatabaseMigrator.registerMigration("v3")` runs cleanly on a v2 DB — verified by the `PermissionsStoreSmokeTests::inMemoryStoreOpensAndMigratesToLatestSchema` assertion bumping to `schemaVersion() == 3`.

Decision: **proceed.** All defaults (snapshot cadence = once per calendar day, retention = 90 days, stale threshold = 90 days, stale scope = TCC-granted apps only) recorded below.

## What shipped

1. **Schema v3 migration** in `PermissionsStore`. Adds `tcc_grants` (service / bundle_id / display_name / bundle_path / last_modified / automation_target) and `btm_items` tables under the existing `snapshots` parent (FK CASCADE). Migration is purely additive — v2 tables untouched.
2. **`DomainChange<T>`** generic carrying `before` and `after`. All three per-domain diff structs (`TCCGrantsDiff`, `BTMItemsDiff`, `LaunchAgentsDiff`) carry `added` / `removed` / `changed` arms plus `hasContent`. The new `changed` arm on `LaunchAgentsDiff` defaults to `[]` so existing call sites compile unchanged.
3. **TCC + BTM write/read/diff API** on `SnapshotStore`. `writeFullSnapshot(grants:launchAgents:btmItems:at:)` is the production entry — one `snapshots` row plus inserts into all three child tables in a single transaction. Per-domain writers stay as test helpers. The BTM enum split (`type_kind` TEXT + nullable `type_raw` INTEGER, `disposition_kind` + `disposition_raw`, `scope_kind` + `scope_per_user_uuid`) round-trips `ItemType.unknown(rawValue:)`, `Disposition.unknown(rawValue:)`, and `Scope.perUser(uuid:)` losslessly.
4. **Snapshot discovery + retention** on `SnapshotStore`. `latestSnapshotID()` and `latestSnapshotID(atOrBefore:)` power the yesterday/last-week diff queries. `pruneSnapshots(olderThan:)` enforces the 90-day retention; FK CASCADE drops child rows.
5. **`StaleApp`** value type in `PermissionsCore`. **`LastUsedProbe`** protocol in `PermissionsCore` alongside the other scanner protocols. **`LastUsedProbeHybrid`** in `PermissionsScanners` shells out to `/usr/bin/mdls -name kMDItemLastUsedDate -raw <path>` with a 2-second timeout race, then falls back to `URL.contentModificationDateKey`, then returns nil. `MockLastUsedProbe` returns fixed dates by URL for tests.
6. **`SnapshotCoordinator`** (`@MainActor final class` in the app target) sits alongside `ScanCoordinator` and `MediaUseCoordinator` under `AppDelegate`. On every `runScan()` / `rescan()` completion, the coordinator:
   - Skips the write if any scanner errored (`viewModel.tccScanError != nil || viewModel.btmScanError != nil`).
   - Compares the `lastSnapshotDate` UserDefaults sentinel (ISO string) against the calendar `today`. Same-day → skip the write but still refresh diffs from the latest snapshot.
   - Calls `writeFullSnapshot(...)`, prunes anything older than 90 days, then queries `latestSnapshotID(atOrBefore: now-24h)` and `(now-7d)`. Runs the three per-domain diffs concurrently via `async let`, packs into `SnapshotDiffs`, pushes to `viewModel`.
   - Computes stale apps via `withTaskGroup` bounded to 8 in-flight `LastUsedProbe` calls. Dedupes grants by `bundleID`, filters to those with a `bundlePath`, applies the 90-day threshold, sorts ascending by `lastUsedDate`.
   - On the What Changed window's `onAppear`, the AppDelegate forwards `markCurrentSnapshotReviewed()` which pins `viewModel.lastReviewedSnapshotID = latestSnapshotID` and persists it as `Int64` to UserDefaults.
7. **`SnapshotPath`** helper in the app target computes `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db` and creates the parent directory if missing. `SnapshotStore.init(path:)` stays unchanged — caller hands in the resolved string.
8. **`AppViewModel` extensions**: `latestSnapshotID`, `lastReviewedSnapshotID`, `latestDiffYesterday`, `latestDiffWeek`, `staleApps`. Computed `hasUnreviewedChanges` = `(latestSnapshotID != lastReviewedSnapshotID) && (latestDiffYesterday?.hasContent ?? false || latestDiffWeek?.hasContent ?? false)`.
9. **6th menu-bar icon state.** New priority chain: `error > unreviewedChanges > cam+mic > cam > mic > idle`. The unreviewed symbol resolves once at first access — `bell.badge.fill` if available, `exclamationmark.bubble.fill` as documented fallback.
10. **What Changed window.** New `WindowGroup(id: "what-changed")` in `PermissionPulseApp`, reached from a new "What Changed" button in `MenuBarContentView` between the status area and "Open Permission Pulse". The button shows an orange dot when `hasUnreviewedChanges` is true. Window structure: `NavigationStack { VStack { segmentedPicker; Divider; ScrollView { tabContent } } }`. Three tabs: Yesterday, Last week, Stale apps. Per-domain change rows use colored indicators (`plus.circle.fill` green / `minus.circle.fill` red / `arrow.triangle.2.circlepath.circle.fill` orange) and localized one-line descriptions.

## Data flow

```
ScanCoordinator.runScan() completes
        │   on full success (no scanner errored)
        ▼
AppDelegate.onScanCompleted → SnapshotCoordinator.onScanCompleted()
        │
        ├─→ check UserDefaults `lastSnapshotDate` vs calendar today
        │       └─→ same day → skip write, just refresh diffs+stale
        │
        ├─→ SnapshotStore.writeFullSnapshot(grants, launchAgents, btmItems)
        │       └─→ pruneSnapshots(olderThan: now-90d)
        │
        ├─→ for each window {now-24h, now-7d}:
        │       latestSnapshotID(atOrBefore: cutoff)
        │       diffTCC / diffBTM / diffLaunchAgents against latest
        │       → AppViewModel.latestDiff{Yesterday,Week} = SnapshotDiffs(...)
        │
        ├─→ stale-app computation (withTaskGroup, ≤8 in-flight)
        │       LastUsedProbeHybrid: mdls → file mtime → skip
        │       → AppViewModel.staleApps = [StaleApp] sorted by lastUsedDate asc
        │
        └─→ AppViewModel.latestSnapshotID = id ; recompute hasUnreviewedChanges
                → menuBarSymbolName flips to bell.badge.fill if true

MenuBarContentView "What Changed" button → openWindow(id: "what-changed")
        → WhatChangedWindowView.onAppear → markCurrentSnapshotReviewed()
        → lastReviewedSnapshotID = latestSnapshotID ; icon returns to base
```

## Files touched

- **New:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/StaleApp.swift`
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/LastUsedProbeHybrid.swift`
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/MockLastUsedProbe.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/LastUsedProbeTests.swift`
  - `Packages/PermissionsStore/Sources/PermissionsStore/DomainChange.swift`
  - `Packages/PermissionsStore/Sources/PermissionsStore/TCCGrantsDiff.swift`
  - `Packages/PermissionsStore/Sources/PermissionsStore/BTMItemsDiff.swift`
  - `Packages/PermissionsStore/Tests/PermissionsStoreTests/TCCDiffTests.swift`
  - `Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDiffTests.swift`
  - `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotDiscoveryTests.swift`
  - `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotRetentionTests.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/SnapshotDiffs.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/WhatChangedWindowView.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift`
  - `Packages/PermissionsUI/Tests/PermissionsUITests/WhatChangedViewModelTests.swift`
  - `PermissionPulse/PermissionPulse/SnapshotPath.swift`
  - `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift`
  - `PermissionPulse/PermissionPulseTests/SnapshotCoordinatorTests.swift`
  - `docs/15-what-changed-and-stale-slice.md` (this file)

- **Modified:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift` — added `LastUsedProbe` protocol.
  - `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` — v3 migration; TCC/BTM write/read/diff; `writeFullSnapshot`; discovery + retention; populate LA `changed` arm; `unsafeChildRowCounts` internal helper for tests.
  - `Packages/PermissionsStore/Sources/PermissionsStore/LaunchAgentsDiff.swift` — added `changed:` (defaults to `[]`) and `hasContent`.
  - `Packages/PermissionsStore/Tests/PermissionsStoreTests/PermissionsStoreTests.swift` — bumped schemaVersion assertion to 3.
  - `Packages/PermissionsStore/Tests/PermissionsStoreTests/LaunchAgentsDiffTests.swift` — bumped schemaVersion assertion; added `runAtLoadFlipAppearsInChangedArm`.
  - `Packages/PermissionsUI/Package.swift` — added `PermissionsStore` dependency.
  - `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` — new stored properties; computed `hasUnreviewedChanges`; updated `menuBarSymbolName` priority chain; `unreviewedSymbolName` with SF Symbol resolution.
  - `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` — "What Changed" button with conditional dot indicator.
  - `Packages/PermissionsUI/Tests/PermissionsUITests/MenuBarSymbolNameTests.swift` — +3 cases for the unreviewed-changes priority.
  - `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` — `WindowGroup(id: "what-changed")` scene; `AppDelegate` owns `snapshotStore` + `snapshotCoordinator`; wires `onScanCompleted()` after `runScan()` and `rescan()`; `markCurrentSnapshotReviewed()` forwarder.
  - `docs/09-roadmap.md` — mark v0.5.0 done.
  - `docs/04-data-sources.md` — update the Last-launch date section with the hybrid implementation + sandboxing future-tag; add a Snapshot store section for v3 schema.
  - `CLAUDE.md` — row in "Known fragile surfaces" for `LastUsedProbeHybrid` (Spotlight unreliability).

## Test coverage

- `TCCDiffTests` — 5 cases (migration, round-trip, added/removed, identical, automationTarget identity).
- `BTMDiffTests` — 6 cases (migration, all-enum-cases round-trip, added/removed, identical, dispositionFlip in changed, perUserUUID round-trip).
- `LaunchAgentsDiffTests` extension — +1 case (`runAtLoadFlipAppearsInChangedArm`).
- `SnapshotDiscoveryTests` — 2 cases (nil-when-none, closest-prior-snapshot).
- `SnapshotRetentionTests` — 2 cases (cascade, keeps-at-or-after-cutoff).
- `LastUsedProbeTests` — 3 cases (mock fixed, mock unknown, hybrid file-system fallback).
- `WhatChangedViewModelTests` — 2 cases (no snapshot → not unreviewed, unreviewed with content → true, reviewed clears).
- `MenuBarSymbolNameTests` extension — +3 cases (unreviewed beats mic/cam, error beats unreviewed, reviewed returns to idle).
- `SnapshotCoordinatorTests` — 5 cases (skip-when-sentinel-matches, write-when-stale, skip-when-errored, push-diffs-and-stale, mark-reviewed).

Test counts: 86 (v0.4.1) → 115 (v0.5.0):
- `PermissionsCore`: 12 (unchanged)
- `PermissionsScanners`: 39 → 42 (+3 LastUsedProbe)
- `PermissionsUI`: 29 → 34 (+2 WhatChangedViewModel, +3 MenuBarSymbolName)
- `PermissionsStore`: 6 → 22 (+5 TCC, +6 BTM, +1 LA, +2 retention, +2 discovery)
- `PermissionPulse` (app target): 0 → 5 (+5 SnapshotCoordinator)

## Icon priority

| State | Symbol |
|---|---|
| `tccScanError != nil` or `btmScanError != nil` | `exclamationmark.shield.fill` |
| `hasUnreviewedChanges` | `bell.badge.fill` (fallback `exclamationmark.bubble.fill`) |
| `micInUse && cameraInUse` | `video.badge.waveform` |
| `cameraInUse` only | `video.fill` |
| `micInUse` only | `mic.fill` |
| neither | `shield.lefthalf.filled` |

Error beats review-state — the user needs to know FDA is not granted before they care about diffs. Review-state beats live state — there's something the user needs to look at, but no active recording.

## Deferred to later slices

- **Per-row "Mark as reviewed" / "Snooze"** actions in What Changed (v0.7.0).
- **"Skip this app forever"** for stale review (v0.7.0).
- **Configurable stale threshold + retention** (v0.7.0 per the roadmap).
- **`auth_value` tracking for TCC** → meaningful `changed` arm. Until then, granted-then-denied looks like remove+add. v0.6.0+.
- **Broader stale-app scope** (all `.app` bundles vs TCC-granted only). v0.7.0 candidate.
- **Tree view of BTM developer-group nesting**. v0.7.0+.
- **Weekly digest notification** of unreviewed changes. v0.7.0 per the roadmap.

## Tahoe-specific risks (documented)

- **GRDB v3 migration on a v2 DB.** v2 tables untouched; only new tables created. `DatabaseMigrator` tracks applied migrations in `grdb_migrations`. `PermissionsStoreSmokeTests` asserts `schemaVersion() == 3` against an in-memory store.
- **Snapshot DB growth.** Worst case ~80 rows/day × 90 days = ~7,200 rows, ~3 MB. `pruneSnapshots(olderThan:)` runs every write. Bound is well under disk-pressure territory.
- **Spotlight `(null)` returns** on a busy machine. Precondition probe showed 3/4 apps null on this machine. Hybrid handles it; skip on both-miss (under-flag, never over-flag).
- **`Process(/usr/bin/mdls)` hang risk.** 2-second timeout race via `Task.sleep`. The mdls binary itself is fast (~50ms typical).
- **`bell.badge.fill` SF Symbol availability.** One-time `NSImage(systemSymbolName:_:)` check at first access with `exclamationmark.bubble.fill` fallback.
- **`Process(/usr/bin/mdls)` in a future sandboxed build.** v0.5.0 is unsandboxed per `CLAUDE.md`, so unrestricted. v0.6.0+ sandbox path: replace with `MDItemCreate` / `MDItemCopyAttribute` in-process. Tagged in `LastUsedProbeHybrid.swift`.
- **Reviewed-state corruption** (`stored lastReviewedSnapshotID > current latest`). Could happen if `snapshots.db` is deleted while UserDefaults survives. Defensive read in `refreshDiffsAndStale`: clear if stored > latest.

## Done means

- All four package test suites pass (`swift test` on each) plus the app target tests (`xcodebuild test`) — 115 tests total.
- `xcodebuild -scheme PermissionPulse -configuration Debug build` succeeds.
- Fresh-DB first launch on Tahoe:
  - `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db` is created.
  - `sqlite3 snapshots.db ".schema"` shows `snapshots`, `launch_agents`, `tcc_grants`, `btm_items`.
  - `SELECT version FROM schema_version` returns 3.
  - Menu-bar icon is `shield.lefthalf.filled` (no error, no diff content yet).
  - "What Changed" button visible in the dropdown.
  - Click it → window opens. Yesterday/Last week tabs show "Permission Pulse needs at least one prior snapshot — come back tomorrow." Stale apps tab shows "No stale apps".
- Second-day diff (advance system clock + Refresh, or wait): a second `snapshots` row is written, Yesterday tab shows added/removed/changed rows if anything moved, icon flips to `bell.badge.fill`. Click "What Changed" → reviewed-state advances, icon returns to `shield.lefthalf.filled`.
- Stale apps: on a machine with a TCC-granted app whose `kMDItemLastUsedDate` or `contentModificationDate` is >90 days ago, the Stale apps tab lists it with the date and source label ("via Spotlight" or "via file modified").
- All v0.4.1 surfaces unchanged: mic/cam icon, FDA empty state, schema-mismatch banner.
