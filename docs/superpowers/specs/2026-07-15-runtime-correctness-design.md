# Permission Pulse v0.7.2 Runtime Correctness Design

**Status:** Approved in brainstorming on 2026-07-15

**Workstream:** B of 3

**Depends on:** Workstream A validation infrastructure

**Required before release:** Workstream C must also pass its gates

## Purpose

Several settings currently persist without affecting the running application, Reset All Data clears disk state without clearing long-lived in-memory stores, and weekly digest scheduling can retain stale timing or produce malformed copy. This workstream makes runtime configuration and destructive lifecycle operations truthful, immediate, and testable.

## Goals

- Apply retention and stale-app thresholds on the next scan without requiring restart.
- Reset persisted and in-memory preferences, dismissal state, notifications, history, and view-model state together.
- Treat database and reset failures as explicit outcomes instead of silently succeeding.
- Reschedule an enabled weekly digest immediately after its day or time changes.
- Keep the displayed next-fire date synchronized with the actual pending request.
- Count TCC authorization transitions in weekly digest copy.

## Non-goals

- Syncing settings between Macs.
- Adding more notification types or changing the weekly digest cadence.
- Replacing UserDefaults or GRDB.
- Performing surprise retention pruning while the user drags a slider; values apply at the next scan boundary.

## Constraints

- All observable preference, reset, coordinator, and view-model mutations remain main-actor isolated.
- Reset may delete only Permission Pulse's Application Support database/sidecars and Permission Pulse-prefixed defaults.
- macOS-owned window, split-view, and status-item defaults remain untouched.
- No reset or preference operation writes to protected system databases, requests elevated privileges, or adds network behavior.
- User-visible strings and errors use the existing localization pattern.
- Runtime changes remain compatible with the macOS 14.6 deployment target and Swift 6 strict concurrency.

## Live Preference Flow

`SnapshotCoordinator` no longer owns copied integer values. Its initializer receives main-actor providers for snapshot retention and stale thresholds. At the start of `onScanCompleted()`, it captures each provider exactly once. That captured pair remains stable for the entire snapshot/prune/stale computation, while the next scan captures any newly persisted values.

`AppViewModel.staleThresholdDays` remains display state and is synchronized before each scan so UI copy and computation use the same captured threshold.

The preference store remains the single source of truth. No second mutable copy of either setting is introduced.

## Reset State Machine

Reset is modeled as a sequence with a structured result rather than a Boolean. The result identifies success or the failed phase and carries user-safe recovery guidance.

Phases execute in this order:

1. **Cancel schedules:** cancel weekly and test notifications owned by Permission Pulse.
2. **Release history:** detach `SnapshotCoordinator` and `SnapshotStore` from the app so no open queue remains owned by the runtime.
3. **Delete history:** remove `snapshots.db`, `snapshots.db-wal`, and `snapshots.db-shm`. Missing files are success; any other removal error is recorded and blocks store recreation/rescan.
4. **Reset live stores:** restore `PreferencesStore` fields to defaults and clear `DismissedDiffEntryStore` and `DismissedStaleAppStore` collections in memory.
5. **Clear defaults:** remove every Permission Pulse-prefixed key while preserving macOS-owned window, split-view, and status-item keys.
6. **Recreate history:** create a fresh migrated `SnapshotStore` at the canonical path and wire a new `SnapshotCoordinator` using live preference providers.
7. **Clear presentation:** remove grants, launch agents, background items, diffs, stale apps, review sentinels, scan timestamps, and transient errors from the view model.
8. **Rescan:** run a fresh scan and snapshot only if every domain is complete.
9. **Reconcile notifications:** reconcile against the reset default `digestEnabled == false`, ensuring no digest is recreated.

Reset is not falsely described as globally atomic because files, defaults, and Notification Center do not share a transaction. It is instead ordered, idempotent, observable, and fail-closed at dependency boundaries. A second reset with already-absent state succeeds.

Each long-lived store provides an explicit reset API:

- `PreferencesStore.resetToDefaults()` updates observable in-memory values.
- `DismissedDiffEntryStore.removeAll()` empties its in-memory map.
- `DismissedStaleAppStore.removeAll()` empties its in-memory key set.

The final defaults cleanup ensures these reset operations do not leave redundant default-valued Permission Pulse keys on disk.

## Digest Scheduling Flow

The digest enabled toggle continues to own authorization. Day and time changes use a separate `PreferencesViewModel` action that:

1. Persists the selected values immediately.
2. Cancels any prior in-flight reschedule task.
3. Reconciles the weekly request after a short debounce so DatePicker intermediate values do not create repeated work.
4. Fetches and publishes the actual next fire date after success.
5. Publishes a localized actionable error after failure while retaining the user's selected preference for retry.

Closing the Preferences window does not cancel a reschedule that has already reached reconciliation. Reopening the window refreshes authorization and pending-fire state from the scheduler.

`WeeklyDigestCoordinator.composeDigestBody` counts all rendered change categories, including `diff.tcc.changed`. A TCC-only transition therefore produces a nonempty localized sentence such as `1 changed in the last week.` The empty-week heartbeat remains unchanged.

## Error Handling

- An unexpected scan/runtime error is not relabeled as a permission denial.
- Database deletion failure prevents recreation over an uncertain path and leaves history unavailable with Retry/Restart guidance.
- Store recreation failure leaves scanning history disabled but does not restore a stale coordinator.
- Defaults cleanup failure is reported as partial reset rather than success.
- Digest scheduling failure does not revert the user's chosen day/time; it exposes retry and recovers during launch reconciliation.
- A reset-triggered rescan failure is reported separately from reset storage completion.

User-facing error text remains localized and does not expose private filesystem details. OSLog retains diagnostic phase and public-safe error descriptions.

## Verification Gates

- Changing retention from 90 to 30 days changes the next scan's prune cutoff without recreating the coordinator.
- Changing stale threshold from 90 to 30 days changes the next scan's stale results and matching UI copy.
- Values remain stable inside one scan even if the preference changes concurrently.
- Reset clears every live store and every persisted Permission Pulse key while preserving macOS-owned defaults.
- Reset removes SQLite main/WAL/SHM files, recreates a v5 database, and performs a clean rescan.
- An injected file-removal failure returns the deletion phase and does not claim success or reuse the old store.
- Reset while digest is enabled leaves no pending digest and sets the live preference to disabled.
- Day/time edits replace the pending request and refresh the next-fire date.
- Rapid time edits produce one final pending weekly request.
- Scheduling failure is visible and retry succeeds without losing the selected time.
- A TCC-only changed diff composes valid singular and plural digest copy.

## Documentation

Update preference and reset documentation to state that thresholds apply on the next scan, describe exactly what Reset All Data clears, and document notification retry behavior.
