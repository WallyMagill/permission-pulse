# 11 — Second slice: TCC scanner

**Status:** Implemented v0.3.0 — 2026-05-14.

**Why this slice:**

- The Permission Inbox is the single highest-value surface in the app. Without it, Permission Pulse is just a launch-agent viewer.
- Both Apple TCC databases use the same `access` table schema. One decoder covers user-DB perms (Camera, Mic, Calendar, Photos, etc.) and system-DB perms (Accessibility, Screen Recording, FDA, Input Monitoring, Developer Tools).
- The scanner ships with proper FDA error handling so the rest of the app keeps working when permission is missing.

## What shipped

1. `TCCScannerSQLite` (`Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift`) reads:
   - `~/Library/Application Support/com.apple.TCC/TCC.db`
   - `/Library/Application Support/com.apple.TCC/TCC.db`

   Reads run in parallel via a task group; results are unioned and sorted by `(service.rawValue, app.bundleID, lastModified.timeIntervalSince1970)`.

2. Two-layer read-only enforcement:
   - GRDB `Configuration.readonly = true` (passes `SQLITE_OPEN_READONLY` to `sqlite3_open_v2`; prevents WAL/SHM sidecar creation).
   - `Configuration.prepareDatabase` issues `PRAGMA query_only = 1` at the connection level.

   The originally-planned `?immutable=1` URI flag was dropped after verifying GRDB v7.10 never sets `SQLITE_OPEN_URI`. See plan doc and `Packages/PermissionsStore/.build/checkouts/GRDB.swift/GRDB/Core/Configuration.swift:476-482`.

3. Schema-version check: `PRAGMA table_info(access)` runs before any row read; throws `ScannerError.schemaMismatch` if any of `{service, client, client_type, auth_value, last_modified}` is missing, `ScannerError.unsupportedOnThisOS` if the table is absent.

4. `PermissionService` enum grew from 7 to 16 cases. Added: `.photos .calendar .contacts .reminders .bluetooth .mediaLibrary .appManagement .inputMonitoring .developerTool`. Six TCC services are skipped with a `.debug` log (Liverpool/HomeKit, Ubiquity/iCloud, FocusStatus, FileProviderDomain, WebBrowserPublicKeyCredential, PostEvent).

5. `auth_value == 2` (allowed) inclusion gate. Denied/limited/unknown rows are skipped silently.

6. Per-DB error aggregation: both DBs fail → throw the first error; one fails → log at `.error`, return the other's rows. v0.3.0 has no partial-data UI so the log is the diagnostic.

7. `ScanCoordinator` swap: `tccScanner` default flipped from `MockTCCScanner()` to `TCCScannerSQLite()`, and `tccDataSource` from `.mock` to `.live`. Two-line change, no structural impact.

8. Menu-bar top-level `MockBadge` removed (task A). Per-section badges in `DetailWindowView` and `LaunchAgentsSection` carry the data-source signal.

## Files touched

- New:
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCFixtures.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCScannerSQLiteTests.swift`
  - `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionServiceMappingTests.swift`
  - `docs/11-tcc-slice.md` (this file)
  - `docs/_tcc-schema-dump-tahoe-26.md`

- Modified:
  - `Packages/PermissionsCore/Sources/PermissionsCore/PermissionService.swift`
  - `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionsCoreTests.swift`
  - `Packages/PermissionsScanners/Package.swift`
  - `Packages/PermissionsScanners/Package.resolved`
  - `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift`
  - `PermissionPulse/PermissionPulse/ScanCoordinator.swift`
  - `docs/04-data-sources.md`
  - `docs/09-roadmap.md`

## Test coverage

- `PermissionServiceMappingTests`: 21 parameterized assertions over the mapping table, 6 over the skip set, 1 unknown-string negative, 1 count assertion. 29 cases total.
- `TCCScannerSQLiteTests`: 13 cases covering happy path, multi-DB union, schema mismatch, unreadable file (CI-gated), unknown/skipped services, empty table, multi-grant same app, denied rows, deterministic ordering, one-DB-fails-other-succeeds, both-fail throws, no sidecar files.
- Existing smoke tests updated: `PermissionsCoreSmokeTests.permissionServiceHasAllExpectedCases` count 7 → 16.

All tests use fixture SQLite files built at test-run time. No committed binary fixtures. No test reads the real machine's TCC.db.

## Schema reference

Captured 2026-05-14 on macOS Tahoe 26 (Darwin 25.4.0). Full dump in `docs/_tcc-schema-dump-tahoe-26.md`. Required columns are stable across both DBs.

## Deferred to later slices

- **FDA UX (Welcome screen, "Grant FDA" CTA, deep-link into System Settings)** → v0.3.1.
- **Schema-mismatch banner in UI** → v0.3.1.
- **Snapshot persistence for TCC grants** (write to `SnapshotStore`, diff API) → v0.5.0 ("What Changed").
- **cdHash / `csreq` verification** for Input Monitoring and others — v0.3.0 attributes by `client` (bundle ID) only → v0.6.0.
- **Display-name resolution** (reading `Info.plist` from the bundle to recover a friendly name) → v0.5.0.
- **Surfacing denied / limited / unknown `auth_value` rows** → v0.6.0 once UI supports the distinction.

## Done means

- All package tests pass (`swift test` on each).
- App target builds via `xcodebuild`.
- `MockTCCScanner` retained as the protocol mock for tests and previews; no longer the production default.
- The Permission Inbox shows real grants from both DBs when the running `.app` has Full Disk Access.
- Without FDA, the inbox is empty and `scanners.tcc` errors appear in OSLog.
