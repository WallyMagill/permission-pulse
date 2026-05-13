# 10 — First slice: LaunchAgents scanner

**Status:** Speced, not implemented.

**Why this slice first:**

- Requires no FDA, so we don't have to ship the permission UX before having anything to show.
- The API surface (`FileManager` + `PropertyListDecoder`) is mainstream Swift — low fragility, no private APIs.
- Exercises the full pipeline: scanner → store → ViewModel → view. After this slice, every later scanner is a "swap one piece" change.

## Acceptance criteria

1. `LaunchAgentScannerFS` (in `PermissionsScanners`) reads:
   - `~/Library/LaunchAgents/`
   - `/Library/LaunchAgents/`
   - `/Library/LaunchDaemons/`
   and returns `[LaunchAgentItem]` parsed from each plist. Items include: label, program path, program arguments, `RunAtLoad`, `KeepAlive`, source directory.
2. `LaunchAgentItem` is defined in `PermissionsCore` and is `Sendable`.
3. `PermissionsStore` gains a `launch_agents` table and a write/diff API for daily snapshots of this data.
4. The detail window has a "Launch Agents" section that lists current items, grouped by source directory, sorted alphabetically by label.
5. The section visually marks mock vs. real data — when the real scanner is wired, the badge says "Live" instead of "Mock".
6. A smoke test in `PermissionsScannersTests`:
   - Uses a temporary directory with three known plists.
   - Asserts the scanner reads all three correctly.
   - Asserts a malformed plist is skipped without throwing.
7. A smoke test in `PermissionsStoreTests`:
   - Writes a snapshot.
   - Writes a second snapshot with one item removed and one added.
   - Diff query returns the correct added/removed sets.

## Files that will change

- `Packages/PermissionsCore/Sources/PermissionsCore/LaunchAgentItem.swift` (already exists from v0.1.0 — verify fields suffice; add `id` if needed for storage)
- `Packages/PermissionsScanners/Sources/PermissionsScanners/LaunchAgentScannerFS.swift` (new)
- `Packages/PermissionsScanners/Tests/PermissionsScannersTests/LaunchAgentScannerFSTests.swift` (new)
- `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` (extend the migrator with a `launch_agents` table; add write/diff API)
- `Packages/PermissionsStore/Tests/PermissionsStoreTests/LaunchAgentsDiffTests.swift` (new)
- `Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentsSection.swift` (new — extract from `DetailWindowView`; takes `Mock`/`Live` badge as input)
- `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (use the extracted section)
- `PermissionPulse/PermissionPulse/ScanCoordinator.swift` (swap `MockLaunchAgentScanner()` for `LaunchAgentScannerFS()`; ditto for the diff store)
- `docs/04-data-sources.md` (mark the LaunchAgents row as "implemented v0.2.0")

## Test plan

- Unit: scanner returns expected count from a temp dir with N fixtures.
- Unit: malformed plist → skipped, not thrown.
- Unit: missing optional keys (`KeepAlive` absent) → default to `false`, item still returned.
- Integration: scanner against the real machine's `~/Library/LaunchAgents/` returns a non-empty array on dev machines that have any agents installed.
- Store: round-trip write/read of a known item set.
- Store: diff between two snapshots returns expected added/removed.
- UI: SwiftUI preview of `LaunchAgentsSection` with both empty and populated states.

## Estimated PR size

Small-medium. Roughly 500 lines of Swift, mostly tests and types.

## Explicit out-of-scope for this slice

- Permission Inbox (TCC data) — that's v0.3.0.
- "What Changed" view — needs more than one snapshot of more than one scanner type. That's v0.5.0.
- Stale App Review — needs both TCC data and last-launch dates. That's v0.5.0.

## Done means

- All tests in the affected packages pass.
- CI is green.
- The detail window's "Launch Agents" section shows the user's real LaunchAgents data with a "Live" badge.
- All other sections still show mock data with "Mock" badges.
- A new commit tagged `v0.2.0` is pushed.
- A GitHub Release is cut (still ad-hoc-signed; release notes hand-written).
