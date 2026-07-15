# 04 — Data sources

Each scanner is documented as: **what it reads, which API, what permission is needed, how fragile it is, what we do when it fails.**

## TCC database (implemented v0.3.0 — user + system DBs)

**What:** Granted TCC permissions per app per service.

**Implementation:** `TCCScannerSQLite` in `PermissionsScanners`. Reads both user and system DBs in parallel via a task group, unions results.

**Where:**
- User TCC: `~/Library/Application Support/com.apple.TCC/TCC.db`
- System TCC: `/Library/Application Support/com.apple.TCC/TCC.db`

**API:** Direct SQLite read via GRDB.

**Permission needed:** Full Disk Access. Without it, the file is unreadable.

**Schema (v1):** Query the `access` table:

- `service` (TEXT) — e.g. `kTCCServiceScreenCapture`, `kTCCServiceAccessibility`, `kTCCServiceSystemPolicyAllFiles`
- `client` (TEXT) — bundle ID
- `client_type` (INTEGER) — 0 = bundle ID, 1 = absolute path
- `auth_value` (INTEGER) — 0=denied, 1=unknown, 2=allowed, 3=limited
- `auth_reason` (INTEGER) — how it was granted
- `auth_version` (INTEGER)
- `csreq` (BLOB) — code signing requirement
- `indirect_object_identifier` (TEXT) — for Automation, the target app's bundle ID
- `flags` (INTEGER)
- `last_modified` (INTEGER) — Unix timestamp

**Fragility:** High. Apple has renamed/added columns in past macOS releases. We:
- Open the DB read-only.
- Probe the column list before reading; surface a "your macOS schema is unknown to this version of Permission Pulse" banner if we see unexpected columns.
- Pin a schema version per macOS major in `PermissionsCore`.

**Failure mode:**
- FDA not granted → show a clear "Grant Full Disk Access to enable the Permission Inbox" empty state. The rest of the app continues to function.
- Schema mismatch → show the banner above; still render columns we recognize.

---

## LaunchAgents and LaunchDaemons (implemented v0.2.0)

**What:** Property-list-defined launch agents (per user) and daemons (system) that auto-run.

**Implementation:** `LaunchAgentScannerFS` in `PermissionsScanners`.

**Where:**
- `~/Library/LaunchAgents/`
- `/Library/LaunchAgents/`
- `/Library/LaunchDaemons/`
- `/System/Library/LaunchAgents/` and `/System/Library/LaunchDaemons/` (read for context but NOT shown by default — these are Apple-owned).

**API:** `FileManager.contentsOfDirectory(at:...)` + `PropertyListDecoder`.

**Permission needed:** None for `~/Library/LaunchAgents/` and the public `/Library/Launch*` paths. FDA NOT required.

**Schema:** Standard `launchd.plist` keys (`Label`, `Program`, `ProgramArguments`, `RunAtLoad`, `KeepAlive`).

**Fragility:** Low. The plist format is stable; the file locations have been the same since Lion.

**Failure mode:**
- File permissions denied on a specific plist → log and skip; continue with the rest.
- Malformed plist → log and skip.

---

## BTM (Background Task Management) — implemented v0.4.0 (direct decode)

**What:** Apps registered with macOS's Background Task Management — the modern unified location for login items, agent daemons, and helper tools.

**Implementation:** `BTMScannerDirect` in `PermissionsScanners`. Reads the highest-versioned `.btm` file on disk via `NSKeyedUnarchiver` (not `PropertyListDecoder` — the file is NSKeyedArchiver-encoded, not a plain plist). The private `ItemRecord` class is registered to a Swift shim (`BTMItemRecordShim`). See `docs/_btm-schema-dump-tahoe-26.md` for the full schema and `docs/13-btm-slice.md` for the slice writeup.

**Where:**
- `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`
- Two versions coexist on Tahoe 26 (`v13`, `v16`). The scanner globs and picks the highest integer suffix.

**API:** Direct decode via `NSKeyedUnarchiver(forReadingFrom:)` with `requiresSecureCoding = false`.

**Permission needed:** Full Disk Access. The directory is root-owned at 0755 but read-gated by TCC; FDA on the `.app` is sufficient — no `sudo` is invoked at runtime (hard rule).

**Fragility:** Very high. No public API. The on-disk class name (`ItemRecord`) and the top-level key (`itemsByUserIdentifier`) are private. Apple bumps the file-version suffix without notice. The shim only reads known fields and ignores unknowns to survive non-breaking schema drift.

**Sentinel user UUIDs:**

| UUID | `BTMItem.Scope` |
|---|---|
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE` | `.user` (root / UID -2) |
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000` | `.system` (UID 0) |
| any other UUID | `.perUser(uuid:)` |

**Failure mode:**
- FDA denied → BTM section shows the FDA empty-state CTA (mirroring the TCC pattern). Menu bar rolls TCC + BTM denials into a single "Full Disk Access needed" attention row.
- Schema not recognized → schema-mismatch banner at the top of the detail window with the running macOS version interpolated; section shows "Background items unavailable — see the banner above".

**Deferred (later slices):**
- `BTMScannerSFL` fallback (`sfltool dumpbtm` via user-invoked `sudo`) — deferred to a future v0.4.x slice if FDA-only proves insufficient. The shipping app must never invoke `sudo` automatically.

---

## Microphone / Camera current use (implemented v0.4.1)

**What:** Whether *any* app is currently using a microphone or camera. Drives the menu-bar icon (`mic.fill`, `video.fill`, or `video.badge.waveform`). Per-app attribution is deferred — see `docs/14-mic-cam-icon-slice.md`.

**Implementation:** `MediaUseObserverCMIO` in `PermissionsScanners` plus `MediaUseCoordinator` in the app target. Pushes `MediaUseEvent`s through an `AsyncStream` into `AppViewModel.micInUse` / `AppViewModel.cameraInUse`.

**API:**
- **Cameras:** `CoreMediaIO` — enumerate `kCMIOHardwarePropertyDevices`, register `CMIOObjectAddPropertyListenerBlock` on `kCMIODevicePropertyDeviceIsRunningSomewhere`. We never open the device.
- **Microphones:** `CoreAudio` — enumerate `kAudioHardwarePropertyDevices`, filter to devices with input streams (`kAudioDevicePropertyStreamConfiguration` on `kAudioDevicePropertyScopeInput`, channels > 0), register `AudioObjectAddPropertyListenerBlock` on `kAudioDevicePropertyDeviceIsRunningSomewhere`.

**Permission needed:** None. No `Info.plist` usage strings, no entitlements, no permission popup. Verified on Tahoe 26 with the diagnostic script. The earlier `AVCaptureDevice.isInUseByAnotherApplication` path is deprecated and returns stale data outside an active capture session — we don't use it.

**Fragility:** Low. CoreMediaIO and CoreAudio property listeners have been stable across many macOS releases and are used by countless camera-indicator utilities.

**Failure mode:**
- Listener registration fails → device is silently skipped (logged via `OSLog`). Other devices continue to fire.
- All listener registrations fail → `micInUse` / `cameraInUse` stay `false`; menu-bar icon stays at idle/error. No crash.

---

## Last-launch date (for Stale App Review — implemented v0.5.0, hybrid)

**What:** When the user last launched a given app. Drives the Stale apps tab in the What Changed window.

**Implementation:** `LastUsedProbeHybrid` in `PermissionsScanners`. Tried in order:
1. `Process(/usr/bin/mdls -name kMDItemLastUsedDate -raw <path>)` — Spotlight metadata. Parsed as `yyyy-MM-dd HH:mm:ss Z` or ISO8601. Wrapped in a 2-second timeout race via `Task.sleep` to bound any pathological hang.
2. `URL.resourceValues(forKeys: [.contentModificationDateKey])` — file-system modification date on the `.app` bundle.
3. nil — `SnapshotCoordinator` skips this app from Stale review.

**Permission needed:** None. `mdls` is unprivileged. `resourceValues` reads via the user's normal filesystem permissions.

**Fragility:** Medium. Spotlight metadata can be stale or unindexed; precondition probing on this machine showed `(null)` for 3 of 4 sample apps. The hybrid handles it.

**Failure mode:** App is omitted from Stale review if neither proxy returns a date. Under-flag, never over-flag.

**Future-tag for sandboxed builds:** v0.5.0 is unsandboxed per `CLAUDE.md`, so `Process(/usr/bin/mdls)` runs unrestricted. If sandboxing is enabled in v0.6.0+, replace the `Process` call with in-process `MDItemCreate` / `MDItemCopyAttribute` from CoreServices. Tagged in `LastUsedProbeHybrid.swift`.

---

## Snapshot store (implemented v0.2.0 LA, v0.5.0 TCC + BTM)

**What:** Local persistence of daily snapshots of TCC grants, BTM items, and LaunchAgents. Powers the What Changed diff queries and Stale App Review.

**Implementation:** `SnapshotStore` in `PermissionsStore` — GRDB v7.x over a single `DatabaseQueue`. Schema:

| Table | Cols | Notes |
|---|---|---|
| `schema_version` | `version: INTEGER` | Single row, currently `4` at the Workstream B gate. Schema v5 is reserved for Data Fidelity Workstream C Task 6 and is not current yet. |
| `snapshots` | `id: INTEGER PK AUTO`, `created_at: DOUBLE` | One row per write. |
| `launch_agents` | snapshot_id FK CASCADE + label / source_directory / program_path / program_arguments_json / run_at_load / keep_alive | v2 migration. |
| `tcc_grants` | snapshot_id FK CASCADE + service / bundle_id / display_name / bundle_path / last_modified / automation_target / auth_value | Created in v3; v4 adds persisted `auth_value` for authorization-transition diffs. |
| `btm_items` | snapshot_id FK CASCADE + identifier / name / developer_name / bundle_identifier / team_identifier / type_kind + type_raw / disposition_kind + disposition_raw / scope_kind + scope_per_user_uuid / modification_date / parent_identifier | v3 migration. The `*_kind` TEXT + nullable `*_raw` INTEGER split round-trips associated-value enum cases. |

**Where:** `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db` via the `SnapshotPath` helper in the app target.

**Write cadence:** Once per calendar day, gated by `UserDefaults` key `com.wallymagill.permissionpulse.lastSnapshotDate` (ISO string). Driven by `SnapshotCoordinator.onScanCompleted()` after a successful scan. If any scanner errored, the write is skipped — diff signal stays clean.

**Retention:** Live user preference, 7–365 days (default 90). `SnapshotCoordinator` captures the current retention value once at each scan-completion boundary, so an edit applies to the next snapshot/prune pass and remains stable within that pass. `SnapshotStore.pruneSnapshots(olderThan:)` runs at each write; FK CASCADE drops child rows.

**Fragility:** Low. GRDB v7.x is locked; migrations are additive.

**Failure mode:** If `SnapshotStore` fails to open (disk full, permissions denied at `~/Library/Application Support`), `AppDelegate` logs and continues. `SnapshotCoordinator` is nil; the rest of the app functions normally. No diffs or Stale apps surface until a future launch resolves the store.

---

## Per-folder grants (Files & Folders)

**What:** TCC entries for specific user folders (Desktop, Documents, Downloads, iCloud Drive, etc.) — service `kTCCServiceSystemPolicyDesktopFolder` and friends.

**API:** Same TCC.db reader as above; service prefix filter.

**Permission needed:** FDA (read of TCC.db).

**Fragility:** Same as TCC.db.

**Failure mode:** Same as TCC.db.

---

## Preferences (implemented v0.7.0)

**What:** User-configurable knobs that previously lived as hardcoded constants in `SnapshotCoordinator`, plus persisted dismissals for diff rows and stale apps.

**Implementation:** `PreferencesStore` in `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesStore.swift`. `@Observable @MainActor` wrapper over `UserDefaults` with clamping on read and write.

**Where:** Standard `UserDefaults` (`com.wallymagill.permissionpulse.*` namespace). See `CLAUDE.md` for the full key list.

**API:** Direct property reads/writes via the typed accessors. Snapshot retention is clamped to 7–365 days and the stale-app threshold to 30–365 days; both default to 90 and are captured from the live store at each scan-completion boundary. The view-model layer (`PreferencesViewModel`) exposes Double mirrors for `Slider` bindings and a digest-time `Date` convenience for `.hourAndMinute` `DatePicker`.

**Permission needed:** None. UserDefaults is unrestricted for our domain.

**Fragility:** Low. The `dismissedDiffEntries` JSON blob is the only structured value; corrupt decode falls back to an empty map.

**Failure mode:** A corrupt JSON blob in `dismissedDiffEntries` logs and is treated as empty; the next write overwrites the bad value.

**Reset:** `ResetAllDataService.reset()` removes every key prefixed with `com.wallymagill.permissionpulse.`, preserving NSWindow/NSStatusItem/NSSplitView system keys.

---

## Weekly digest notification (implemented v0.7.0, opt-in)

**What:** A single weekly local notification summarizing changes since the last digest. Body composed from `viewModel.latestDiffWeek`.

**Implementation:** `WeeklyDigestScheduler` protocol in `PermissionsCore`; `LiveWeeklyDigestScheduler` (wraps `UNUserNotificationCenter.current()`) in `PermissionsScanners`; `MockWeeklyDigestScheduler` actor for tests; `WeeklyDigestCoordinator` in the app target owns reconcile + auth + body composition.

**API:** `UNCalendarNotificationTrigger(repeats: true)` keyed on weekday + hour + minute. Identifier prefix `com.wallymagill.permissionpulse.digest.weekly`; cancel-then-schedule on every reconcile keeps exactly one pending request at a time.

**Permission needed:** `UNUserNotificationCenter.requestAuthorization`. Prompted on first opt-in (Preferences toggle); macOS shows the system dialog. No `Info.plist` usage string is required on macOS.

**Fragility:** Medium. An unsigned `.app` may show a generic bundle label in the prompt and delivered notification; see the "Known fragile surfaces" row in `CLAUDE.md`. Hand-test before each release that ships the digest.

**Failure mode:** If authorization is denied, the Preferences "Notifications are off" hint shows a deep-link to the System Settings → Notifications pane via `SystemSettingsLink.openNotifications()`. Toggle stays in the user's selected position so the discrepancy is visually obvious.

---

## Permission summary

| Source | Permission required | Fragility | If unavailable |
|---|---|---|---|
| TCC.db | FDA | High | Inbox shows "needs FDA" empty state (✅ implemented v0.3.0) |
| LaunchAgents/Daemons (public) | None | Low | always works (✅ implemented v0.2.0) |
| BTM (direct .btm) | FDA | Very high | section shows FDA empty state (✅ implemented v0.4.0) |
| BTM (sfltool) | Manual sudo | High | deferred (would be a manual user step, not automation) |
| Mic/Cam observation | None | Low | menu-bar icon stays at idle/error (✅ implemented v0.4.1) |
| Last-launch date (hybrid) | None | Medium | app omitted from Stale review (✅ implemented v0.5.0) |
| Snapshot store (GRDB) | None | Low | What Changed window shows no-prior-snapshot state (✅ implemented v0.5.0) |
