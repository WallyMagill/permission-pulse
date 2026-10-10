# Core loop: scheduled scans and coverage-aware history — design

Date: 2026-10-10 · Branch: `feat/core-loop` · Overhaul piece A of three (A core loop → C inventory cleanup → B "Needs a look" home queue). Approved in chat by Walter 2026-10-10 (option A2).

## Problem

The "what changed" feature has never produced a diff on Walter's Mac.

- `~/Library/LaunchAgents/com.google.keystone.agent.plist` and `com.google.keystone.xpcservice.plist` are empty `{}` plists. `LaunchAgentScannerFS` fails to decode `Label`, counts each as an omitted entry, and returns a `.entries` warning → Launch Agents availability is `.degraded`.
- `SnapshotCoordinator.scanFullySucceeded()` requires all three domains `.complete`, so every snapshot write is skipped. The live `snapshots.db` holds two snapshots, both 2026-09-09 (seed rows).
- Scans run only at launch and on manual Rescan. The app ran 2026-09-29 → 2026-10-09 with one scan.
- Snapshots are written at most once per calendar day, so a grant added today is invisible until tomorrow's first scan.

Result: Recent Changes permanently reads "No snapshot from yesterday yet", the dropdown never shows change rows, the weekly digest has nothing to say.

## Goals

1. One degraded or failed domain never blocks history for the other domains.
2. A change on disk shows up in Recent Changes the same day, without a manual Rescan.
3. Keep the under-flag rule: never show an "added"/"removed" row derived from incomplete evidence.
4. A stalled history is visible, not silent.

Non-goals: the Yesterday / Last 7 days picker vs "Since last review" (piece B), duplicate rows and naming (piece C), any change to what the scanners read.

## Design

### 1. Label-less plists are inert, not malformed

`LaunchAgentScannerFS.decodePlist` distinguishes three outcomes:

- Parses as a dictionary with a string `Label` → item (unchanged).
- Parses as a dictionary with **no `Label` key** → inert. launchd refuses to load such a file, so it is not a launch agent. Not listed, not counted as omitted, no warning.
- Unreadable, not a plist, not a dictionary, or `Label` present but not a string → omitted (unchanged; still produces the `.entries` warning).

### 2. Scan triggers

New `ScanScheduler` (app target, `@MainActor`) owns *when* to scan; `AppDelegate.rescan()` stays the single *how*. Triggers:

| Trigger | Source |
|---|---|
| Launch | existing `applicationDidFinishLaunching` scan |
| Wake from sleep | `NSWorkspace.didWakeNotification` on `NSWorkspace.shared.notificationCenter` |
| New calendar day | `.NSCalendarDayChanged` on `NotificationCenter.default` |
| Dropdown or detail window appears and last scan is older than `staleScanInterval` | `onAppear` callbacks passed into `MenuBarContentView` / `DetailWindowView` |

`staleScanInterval = 15 minutes` — a guess: frequent enough that opening the menu shows current state, rare enough that browsing doesn't rescan constantly. Each scan logs its duration (`scan-coordinator` OSLog category, `.info`) so the number can be retuned from measurements. Overlapping triggers coalesce through the existing `performRescanIfIdle` guard. Notification centers and the clock are injected for tests.

### 3. Write a snapshot when the evidence changed

Replace "at most one snapshot per calendar day, only when all domains are complete" with:

After every scan, compare the current scan to the latest stored snapshot. Write a new snapshot when **any** of:

- there is no stored snapshot;
- any domain's coverage differs from the latest snapshot's coverage;
- for any domain that is not `failed` in the current scan, the store diff (same identity + equivalence rules as `diffTCCGrants` / `diffBTMItems` / `diffLaunchAgents`) between the latest snapshot and the current items has content.

Otherwise skip (log "unchanged"). The comparison reuses the store's existing diff semantics through a new array-level entry point, so "changed" means exactly what Recent Changes renders from.

Volume receipt: on Walter's Mac, 12 of 284 user TCC rows and 2 of 82 system rows had `last_modified` inside the last 7 days (measured 2026-10-10), so change-driven writes add a handful of snapshots per week.

`lastSnapshotDate` in UserDefaults is no longer a write gate; it is still written after each snapshot (Reset All Data and existing tests reference the key).

### 4. Per-domain coverage on each snapshot (schema v6)

Migration `v6` adds to `snapshots`:

- `tcc_coverage TEXT NOT NULL DEFAULT 'complete'`
- `btm_coverage TEXT NOT NULL DEFAULT 'complete'`
- `launch_agent_coverage TEXT NOT NULL DEFAULT 'complete'`

Values: `complete`, `degraded`, `failed` (new `SnapshotCoverage` enum in `PermissionsStore`). Existing v5 rows default to `complete`, which is true: v5 only ever wrote fully complete scans. `schema_version` → 6.

Write rules per domain:

- `complete` / `degraded` → store the items the scan returned.
- `failed` → store no rows for that domain in this snapshot.

The unmerged `codex/agent-access-*` branches also register a migration named `v6`; if revived they must renumber to `v7`.

### 5. Diffing compares only complete-to-complete

For each window (Yesterday: latest snapshot at or before start of today; Last 7 days: latest at or before start of today − 7 days), per domain:

- both endpoint snapshots `complete` for that domain → diff as today;
- otherwise → that domain's diff is empty and the domain is listed in `SnapshotDiffs.uncomparedDomains`.

`SnapshotDiffs` gains `uncomparedDomains: [HistoryDomain]` (`tcc`, `btm`, `launchAgents`; new enum in `PermissionsUI`, distinct from the 2-case `ScannerDomain`). `hasContent` is unchanged (rendered rows only).

### 6. Retention keeps the baseline

With change-only writes, the newest snapshot can be weeks old and still be the current baseline. `pruneSnapshots(olderThan:)` keeps the newest snapshot at or before the cutoff (it represents the state at the cutoff) and the overall latest snapshot; it deletes older ones.

### 7. Make history status visible

Recent Changes shows, below the window picker:

- "History updated <date>" — the latest snapshot's timestamp.
- When `uncomparedDomains` is non-empty: "Launch Agents weren't compared — a scan in this window was incomplete." (one line per domain, localized).

The weekly digest body must not read as "no changes" when a domain was not compared: if the week diff has no content but `uncomparedDomains` is non-empty, it says "No changes found in compared data; <domain> couldn't be compared this week."

## Components touched

| Unit | Change |
|---|---|
| `PermissionsScanners/LaunchAgentScannerFS.swift` | inert classification |
| `PermissionsStore/SnapshotStore.swift` | v6 migration, coverage on write, `coverage(for:)` read, array-level diff entry point, baseline-preserving prune |
| `PermissionsStore/SnapshotCoverage.swift` (new) | enum |
| `PermissionsUI/SnapshotDiffs.swift`, `HistoryDomain.swift` (new) | `uncomparedDomains` |
| `PermissionsUI/DiffTabView.swift`, `DetailWindowView.swift` (Recent Changes page) | history status lines |
| `PermissionsUI/MenuBarContentView.swift`, `DetailWindowView.swift` | `onAppear` staleness callback |
| `PermissionPulse/SnapshotCoordinator.swift` | change-driven write, coverage mapping, per-domain diff gating |
| `PermissionPulse/ScanScheduler.swift` (new) | triggers |
| `PermissionPulse/ScanCoordinator.swift` | duration log |
| `PermissionPulse/PermissionPulseApp.swift` | wire scheduler + callbacks |
| `PermissionPulse/WeeklyDigestCoordinator.swift` | uncompared wording |

`SnapshotStore.swift` is 647 lines; if additions push it past the 800-line cap, split diff helpers into `SnapshotStore+Diff.swift`.

## Error handling

- Snapshot write failure: logged at `.error` (unchanged); diffs refresh from the previous latest.
- Coverage read of a v5-era row returns `complete` via the column default.
- Unknown coverage string in the DB (future downgrade) → treated as `failed` for diffing (under-flag) and logged.

## Testing (Swift Testing, one per behavior)

- Scanners: empty-dict plist → no item, no warning; non-plist file → omitted + warning (existing test kept).
- Store: v5 fixture DB migrates to v6 with coverage `complete` on existing rows; coverage round-trips; failed domain writes no rows; prune keeps the baseline snapshot and the latest.
- Coordinator: degraded Launch Agents still writes a snapshot; unchanged scan writes nothing; changed scan writes a second snapshot the same day; window diff lists a degraded endpoint domain in `uncomparedDomains` and shows no rows for it.
- Scheduler: wake, day-change, and stale-open each request exactly one scan; a fresh open (< 15 min) requests none.
- Digest: uncompared wording.

Run: `swift test --package-path Packages/<each>` and the app test target via `xcodebuild test`.

## Regression risks and how we'd notice

- Weekly digest content — `WeeklyDigestCoordinatorTests`.
- Reset All Data — `ResetAllDataServiceTests` (clears `lastSnapshotDate`, diffs).
- Unreviewed badge — `hasUnreviewedChanges` now flips on same-day snapshots; covered by existing AppViewModel tests plus the same-day coordinator test.
- Live verification on Walter's Mac: after install, the next scan writes snapshot #3 with `launch_agent_coverage = 'complete'` (Keystone files now inert), visible via `sqlite3 -readonly`.
