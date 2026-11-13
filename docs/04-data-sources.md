# 04 — Data sources

Each scanner is documented as: **what it reads, which API, what permission is needed, how fragile it is, what we do when it fails.**

## TCC database (implemented v0.3.0 — user + system DBs)

**What:** Granted TCC permissions per app per service.

**Implementation:** `TCCScannerSQLite` in `PermissionsScanners`. Reads both user and system DBs in parallel via a task group, unions results.

**Where:**
- User TCC: `~/Library/Application Support/com.apple.TCC/TCC.db` — **macOS 26 and earlier only.**
- System TCC: `/Library/Application Support/com.apple.TCC/TCC.db`

**macOS 27 hides the per-user database.** Observed on macOS 27.2 (build 26B123): `~/Library/Application Support/com.apple.TCC/` no longer exists, and the per-user `tccd` keeps its database under `/private/var/containers/Data/ProtectedSystem/<UUID>/…/com.apple.TCC/TCC.db`, which a Full Disk Access process cannot list or open (`Operation not permitted`). There is no supported way to read it, and the hard rules forbid escalating. The scanner therefore reports the user database as an *unexposed source* (`ScannerOutput.unavailableSources`) when its directory is absent, or on macOS 27+ when the directory exists but holds no `TCC.db` — not as a warning — and the scan is complete for the system database alone. On that Mac the system database held Accessibility, Full Disk Access, Input Monitoring, and Screen Recording; App Management, Automation, Bluetooth, Calendars, Camera, Contacts, Files and Folders, Media Library, Microphone, Photos, and Reminders had been in the per-user database and are no longer visible. The system database also carries Remote Desktop (`kTCCServiceRemoteDesktop`) and Endpoint Security (`kTCCServiceEndpointSecurityClient`) grants, which the app maps to services of their own. These six make up `PermissionService.systemLevel`. The Permissions banner reads "System-level permissions only" and snapshots record `tcc_coverage = 'reduced'`. A search for a hidden service (for example Camera) says "macOS 27 doesn't let apps see which apps have Camera access" and offers that System Settings pane; the dropdown, Overview ("Permission coverage: System-level only (macOS 27)"), the app inspector, and Stale Apps state the same scope.

**Services (18):** Accessibility, Screen Recording, Full Disk Access, Microphone, Camera, Automation, Files and Folders, Photos, Calendar, Contacts, Reminders, Bluetooth, Media Library, App Management, Input Monitoring, Developer Tools, Remote Desktop, Endpoint Security. Remote Desktop and Endpoint Security have no verified per-service System Settings anchor and link to the top-level Privacy & Security pane. Other `kTCCService…` strings are skipped.

**Display-time check:** a grant whose app is no longer installed gets an "App not found on this Mac" badge. It flags only when sure: a bundle ID that neither Launch Services nor a parent bundle ID resolves, or a client path that `lstat` reports as missing. Nothing is stored.

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
- One user/system database unreadable → return the other database's rows with a source warning; the page shows degraded data and the snapshot records `tcc_coverage = 'degraded'`, which history does not compare.
- Both databases unreadable (including FDA denial) → throw. Preserve and label last-known rows when available; otherwise show a clear no-successful-data state with the FDA action.
- Schema mismatch → show the banner above and preserve prior successful rows rather than relabeling the error as permission denial.

---

## LaunchAgents and LaunchDaemons (implemented v0.2.0)

**What:** Property-list-defined launch agents (per user) and daemons (system) that auto-run.

**Implementation:** `LaunchAgentScannerFS` in `PermissionsScanners`.

**Where:**
- `~/Library/LaunchAgents/`
- `/Library/LaunchAgents/`
- `/Library/LaunchDaemons/`
- `/System/Library/LaunchAgents/` and `/System/Library/LaunchDaemons/` are not read (Apple-owned).
- launchd's disabled-override database: `/private/var/db/com.apple.xpc.launchd/disabled.plist` (the system domain, used for `/Library/LaunchDaemons` jobs) and `disabled.<uid>.plist` for the current user (used for both LaunchAgents directories). Both are world-readable `label → Bool` dictionaries that `launchctl disable`/`enable` and System Settings → Login Items write. `LaunchdDisabledOverrides` reads them once per scan, read-only. An entry there overrides the plist's `Disabled` key; a missing or unreadable file means no overrides, never an error.

**API:** `FileManager.contentsOfDirectory(at:...)` + `PropertyListSerialization`.

**Permission needed:** None for `~/Library/LaunchAgents/` and the public `/Library/Launch*` paths. FDA NOT required.

**Schema:** Standard `launchd.plist` keys (`Label`, `Program`, `ProgramArguments`, `RunAtLoad`, `KeepAlive`, `Disabled`), read leniently: an optional key of the wrong type reads as absent instead of dropping the job. The item also records the plist's file name on disk (`fileName`).

**Fragility:** Low. The plist format is stable; the file locations have been the same since Lion.

**Display:** each row shows the label, the program's file name and the scope ("User", "All users", or "System daemon"), and a Disabled badge when launchd has the job disabled. When the program the job names does not exist on disk, the row says "Program not found — likely left behind by an uninstalled app".

**Failure mode:**
- An existing source directory unreadable → retain results from readable sources and return a source warning.
- A plist that is permission-denied (for example a root-only 0700 daemon plist) or cannot be parsed → listed as an item with `detailsReadable = false`, labelled by its file name, shown as "Details unreadable", with no warning. Its program, arguments, and flags carry no evidence.
- A dangling symlink, or a well-formed plist with no `Label` (launchd ignores it) → skipped silently.
- Any other unreadable entry (another read error, a non-dictionary plist, a non-string `Label`) → retain valid items and return an omitted-entry warning naming the files. The page banner shows it as information ("Some entries skipped"); it does not raise the menu-bar warning.
- A full scan failure preserves and labels last-known rows. A warning records the domain's snapshot coverage as `degraded`; a failure records it as `failed` with no rows. Neither is compared against a complete snapshot, so it cannot create false removals.

---

## BTM (Background Task Management) — implemented v0.4.0 (direct decode)

**What:** Apps registered with macOS's Background Task Management — the modern unified location for login items, agent daemons, and helper tools.

**Implementation:** `BTMScannerDirect` in `PermissionsScanners`. Reads the highest-versioned `.btm` store on disk via `NSKeyedUnarchiver` (not `PropertyListDecoder` — the file is NSKeyedArchiver-encoded, not a plain plist). The private `ItemRecord` class is registered to a Swift shim (`BTMItemRecordShim`). See `docs/_btm-schema-dump-tahoe-26.md` for the full schema and `docs/13-btm-slice.md` for the slice writeup.

**Where:**
- `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`
- Two versions coexist on Tahoe 26 (`v13`, `v16`). The scanner globs and picks the highest integer suffix.
- **macOS 27 (store v18) splits the store per user.** `BackgroundItems-v18.btm` is an index (`$top`: `version`, `infoByUserIdentifier`, `mdmPayloadsByIdentifier`) with no items. Items live in `BackgroundItems-v18-<user UUID>.btm`, whose `$top.userStore` is a `BTMUserStore` (`userIdentifier`, `records`, `userSettings`, `lastUsedDate`); `records` is the `ItemRecord` list, unchanged apart from a new `lastUseDate`. When the newest version has per-user files the scanner reads all of them (shim: `BTMUserStoreShim`); otherwise it reads the single file. One unreadable per-user file, or a user the index lists with no file, fails the scan, because missing items would read as removals.

**API:** Direct decode via `NSKeyedUnarchiver(forReadingFrom:)` with `requiresSecureCoding = false`.

**Permission needed:** Full Disk Access. The directory is root-owned at 0755 but read-gated by TCC; FDA on the `.app` is sufficient — no `sudo` is invoked at runtime (hard rule).

**Fragility:** Very high. No public API. The on-disk class name (`ItemRecord`) and the top-level key (`itemsByUserIdentifier`) are private. Apple bumps the file-version suffix without notice. The shim only reads known fields and ignores unknowns to survive non-breaking schema drift.

**Sentinel user UUIDs:**

| UUID | `BTMItem.Scope` |
|---|---|
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE` | `.user` (root / UID -2) |
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000` | `.system` (UID 0) |
| any other UUID | `.perUser(uuid:)` |

**Identity:** the same identifier is registered once per scope (system, root user, each login user), so an item's identity is scope + identifier (`BTMItem.identityKey`, e.g. `system|2.us.zoom.xos`). Change rows name the scope when one identifier appears in more than one.

**Item types:** the record's `type` is a private integer. `BTMItem.ItemType` names the values seen on macOS 26/27, identified from the item paths each one registers:

| Raw `type` | Case | Shown as |
|---|---|---|
| `0x2` | `.app` | App |
| `0x4` | `.loginItem` | Login item |
| `0x8` | `.agent` | App agent |
| `0x20` | `.developerGroup` | Developer group |
| `0x40` | `.spotlightImporter` | Spotlight extension |
| `0x80` | `.dockTilePlugin` | Dock tile extension |
| `0x800` | `.quickLookExtension` | QuickLook extension |
| `0x2000` | `.backgroundTasks` | Background tasks |
| `0x10008` | `.legacyAgent` | Legacy agent |
| `0x10010` | `.legacyDaemon` | Legacy daemon |
| anything else | `.unknown(rawValue:)` | Unknown (0x…) |

Snapshots store the stable `kindName` (`app`, `loginItem`, …) in `type_kind`. Rows stored by earlier builds as `unknown` with a raw value that now has a name decode to the named case, so upgrading reports no change.

**Diffs** compare disposition (enabled/disabled) and type only; name, developer, date, and raw-bit churn neither creates a change row nor a new snapshot.

**Failure mode:**
- FDA denied → BTM throws; the section preserves and labels last-known rows or shows an explicit no-history FDA state. Menu-bar attention rolls TCC + BTM denials into one action.
- Schema not recognized → schema-mismatch banner with the running macOS version; prior successful rows remain labeled stale when available.

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

**Device changes:** listeners on `kAudioHardwarePropertyDevices` and `kCMIOHardwarePropertyDevices` re-read the device lists; `MediaDeviceTracker` adds listeners for new devices, drops them for devices that left, and re-emits the combined in-use state, so a device plugged in after launch is watched and one unplugged while in use does not leave the indicator on.

**Menu-bar priority:** live microphone or camera use wins the icon over a warning or unreviewed changes; the accessibility label names both when both apply.

**Failure mode:**
- Listener registration fails → device is silently skipped (logged via `OSLog`). Other devices continue to fire.
- All listener registrations fail → `micInUse` / `cameraInUse` stay `false`; menu-bar icon stays at idle/error. No crash.

---

## Last-launch date (for Stale App Review — implemented v0.5.0, hybrid)

**What:** When the user last launched a given app. Drives the Stale apps tab in the What Changed window.

**Implementation:** `LastUsedProbeHybrid` in `PermissionsScanners`. Only `.app` bundles are probed: for a bare binary such as `/usr/libexec/sshd-keygen-wrapper`, Spotlight's last-used date is its modification time (the OS update), so a tool used daily would read as stale. Tried in order:
1. `Process(/usr/bin/mdls -name kMDItemLastUsedDate -raw <path>)` — Spotlight metadata. Parsed as `yyyy-MM-dd HH:mm:ss Z` or ISO8601. Wrapped in a 2-second timeout race via `Task.sleep` to bound any pathological hang.
2. `URL.resourceValues(forKeys: [.contentModificationDateKey])` — file-system modification date on the `.app` bundle. The Stale Apps row then reads "Last modified <date>" instead of "Last used <date>".
3. nil — `SnapshotCoordinator` skips this app from Stale review.

**Permission needed:** None. `mdls` is unprivileged. `resourceValues` reads via the user's normal filesystem permissions.

**Fragility:** Medium. Spotlight metadata can be stale or unindexed; precondition probing on this machine showed `(null)` for 3 of 4 sample apps. The hybrid handles it.

**Failure mode:** App is omitted from Stale review if neither proxy returns a date. Under-flag, never over-flag.

**Future-tag for sandboxed builds:** v0.5.0 is unsandboxed per `CLAUDE.md`, so `Process(/usr/bin/mdls)` runs unrestricted. If sandboxing is enabled in v0.6.0+, replace the `Process` call with in-process `MDItemCreate` / `MDItemCopyAttribute` from CoreServices. Tagged in `LastUsedProbeHybrid.swift`.

---

## Snapshot store (implemented v0.2.0 LA, v0.5.0 TCC + BTM)

**What:** Local persistence of snapshots of TCC grants, BTM items, and LaunchAgents, written whenever the evidence or coverage changes. Powers the What Changed diff queries and Stale App Review.

**Implementation:** `SnapshotStore` in `PermissionsStore` — GRDB v7.x over a single `DatabaseQueue`. Schema:

| Table | Cols | Notes |
|---|---|---|
| `schema_version` | `version: INTEGER` | Single row, currently `7`. GRDB's own `grdb_migrations` table records the applied migration identifiers `v1` through `v7`. |
| `snapshots` | `id: INTEGER PK AUTO`, `created_at: DOUBLE`, `launch_agent_disabled_captured: INTEGER`, `tcc_coverage` / `btm_coverage` / `launch_agent_coverage: TEXT` | One row per write. Migrated v4 rows carry capture marker `0`; v5+ snapshots write `1`. v6 adds per-domain coverage (`complete` / `reduced` / `degraded` / `failed`; `reduced` means everything this macOS exposes was captured but that is less than `complete` covers); pre-v6 rows default to `complete`, which is true because v5 only wrote fully complete scans. |
| `launch_agents` | snapshot_id FK CASCADE + label / source_directory / program_path / program_arguments_json / run_at_load / keep_alive / is_disabled / details_readable / file_name | v2 table; v5 persists disabled state. Disabled-only comparison is enabled only when both snapshots carry the v5 marker. v7 adds `details_readable` (INTEGER NOT NULL DEFAULT 1, true for every earlier row, which all came from readable plists) and nullable `file_name` (NULL on earlier rows). `details_readable` takes part in comparison; `file_name` does not, so the first scan after upgrading reports no change. |
| `tcc_grants` | snapshot_id FK CASCADE + service / bundle_id / display_name / bundle_path / last_modified / automation_target / auth_value | Created in v3; v4 adds persisted `auth_value` for authorization-transition diffs. |
| `btm_items` | snapshot_id FK CASCADE + identifier / name / developer_name / bundle_identifier / team_identifier / type_kind + type_raw / disposition_kind + disposition_raw / scope_kind + scope_per_user_uuid / modification_date / parent_identifier | v3 migration. The `*_kind` TEXT + nullable `*_raw` INTEGER split round-trips associated-value enum cases. |

**Where:** `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db` via the `SnapshotPath` helper in the app target.

**Write cadence:** Change-driven. After every scan `SnapshotCoordinator.onScanCompleted()` writes a snapshot when none exists, when any domain's coverage differs from the latest snapshot's, or when the store's own diff rules (`SnapshotStore.evidenceChanged`) find a difference in any domain that did not fail; an unchanged scan writes nothing, and a scan where every domain failed writes nothing. A `complete` or `degraded` domain stores the rows it returned; a `failed` domain stores none. "Evidence" means only what the app shows: a grant's authorization state, a background item's disposition and type, and a launch agent's program, arguments, flags, readability, and disabled state.

**Baselines and windows:** Recent Changes has two windows. **Since Last Review** compares with the snapshot the user last reviewed (`lastReviewedSnapshotID`); with none recorded it uses the start of today. The first snapshot ever, and the first after Reset All Data, is recorded as reviewed, so later changes show as changes since it. Leaving Recent Changes, closing the detail window while it shows Recent Changes, or choosing **Mark All Reviewed** records the latest snapshot as reviewed. **Last 7 days** compares with the state at the start of the day seven days ago. Each domain picks its own baseline (`BaselineSelector`): the newest snapshot at or before the window's cutoff whose coverage can be compared with the latest one's. `complete`↔`complete` and `reduced`↔`reduced` compare normally; a `complete` baseline against a `reduced` latest (macOS 26 history, macOS 27 scan) compares only the system-level services and the page says "Compared system-level permissions only"; a `reduced` baseline cannot serve a `complete` latest. A domain without a usable baseline is not compared, and the page says why: macOS changed what is readable (`scopeChanged`), the latest scan could not read it (`latestScanFailed`; for Permissions and Background Items the line adds "usually because Full Disk Access is off"), some items could not be read (`itemsUnreadable`), or no earlier snapshot recorded it (`noEarlierSnapshot`). The page also states each domain's baseline date. `com.wallymagill.permissionpulse.lastSnapshotDate` is still written after each snapshot but no longer gates writes. Scans run at launch, on wake, on calendar-day change, and when the dropdown or detail window opens more than 60 seconds after the last scan (`ScanScheduler`).

**Retention:** Live user preference, 7–365 days (default 90). `SnapshotCoordinator` captures the current retention value once at each scan-completion boundary, so an edit applies to the next snapshot/prune pass and remains stable within that pass. `SnapshotStore.pruneSnapshots(olderThan:keeping:)` runs at each write. It keeps the latest snapshot, the newest one at or before the cutoff, per domain the newest snapshot of each full scope (`complete`, `reduced`) at or before the cutoff, every baseline a current window compares against, and the last-reviewed snapshot; FK CASCADE drops child rows.

**Fragility:** Low. GRDB v7.x is locked; migrations are additive. A schema v4, v5, or v6 database migrates to v7 in place on first open.

**Failure mode:** If `SnapshotStore` fails to open, `AppDelegate` logs and continues. `SnapshotCoordinator` is nil; the rest of the app functions normally, and Recent Changes says which problem it is:
- A database whose recorded migrations this build does not know (written by a newer Permission Pulse) → "History From a Newer Version: … Update the app to keep using it." The file is not migrated or changed.
- `SQLITE_CORRUPT` or `SQLITE_NOTADB` → "History Is Damaged: … Use Reset All Data in Settings → Data to start a new history."
- Anything else (disk full, permissions denied at `~/Library/Application Support`) → "History Unavailable".

A write that finds the database locked by another process waits up to 5 seconds. A failed snapshot write shows "Couldn't save the latest snapshot" on Recent Changes.

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

**Where:** Standard `UserDefaults` (`com.wallymagill.permissionpulse.*` namespace). See the "UserDefaults keys" section of `AGENTS.md` for the full key list; v0.7.2 added `changeAlertsEnabled` (Bool, default false, in `PreferencesStore`) and, written by the app delegate, `lastLaunchedVersion` and `fdaPromptShownForVersion` (strings of the form `"<short version> (<build>)"`).

**API:** Direct property reads/writes via the typed accessors. Snapshot retention is clamped to 7–365 days and the stale-app threshold to 30–365 days; both default to 90 and are captured from the live store at each scan-completion boundary. The view-model layer (`PreferencesViewModel`) exposes Double mirrors for `Slider` bindings and a digest-time `Date` convenience for `.hourAndMinute` `DatePicker`.

**Permission needed:** None. UserDefaults is unrestricted for our domain.

**Fragility:** Low. The `dismissedDiffEntries` JSON blob is the only structured value; corrupt decode falls back to an empty map.

**Failure mode:** A corrupt JSON blob in `dismissedDiffEntries` logs and is treated as empty; the next write overwrites the bad value.

**Reset:** `ResetAllDataService.reset()` removes every key prefixed with `com.wallymagill.permissionpulse.`, preserving NSWindow/NSStatusItem/NSSplitView system keys.

---

## Weekly digest notification (implemented v0.7.0, opt-in)

**What:** A single weekly local notification summarizing the visible changes (dismissed and snoozed ones excluded) in the "Last 7 days" window. Body composed from `viewModel.latestDiffWeek`; it names any domain that could not be compared and never claims "no changes" for data that was not compared.

**Implementation:** `WeeklyDigestScheduler` protocol in `PermissionsCore`; `LiveWeeklyDigestScheduler` (wraps `UNUserNotificationCenter.current()`) in `PermissionsScanners`; `MockWeeklyDigestScheduler` actor for tests; `WeeklyDigestCoordinator` in the app target owns reconcile + body composition. Authorization goes through `NotificationAuthorization`, shared with change alerts.

**API:** `UNCalendarNotificationTrigger(repeats: false)` keyed on weekday + hour + minute: only the next occurrence is armed. The digest is reconciled after every scan (the launch scan included) and on every Preferences change, so the body always reflects the latest scan and an old body is never delivered again. Identifier prefix `com.wallymagill.permissionpulse.digest.weekly`; cancel-then-schedule on every reconcile keeps exactly one pending request at a time.

**Permission needed:** `UNUserNotificationCenter.requestAuthorization`. Prompted on the first opt-in to either the digest or change alerts (Preferences → Notifications); macOS shows the system dialog. No `Info.plist` usage string is required on macOS.

**Fragility:** Medium. An unsigned `.app` may show a generic bundle label in the prompt and delivered notification; see the "Known fragile surfaces" row in `AGENTS.md`. Hand-test before each release that ships the digest or change alerts.

**Failure mode:** If authorization is denied, the Preferences "Notifications are off in System Settings." hint shows a deep-link to the System Settings → Notifications pane via `SystemSettingsLink.openNotifications()`. Toggle stays in the user's selected position so the discrepancy is visually obvious.

---

## Change alerts (implemented v0.7.2, opt-in)

**What:** One local notification when a scan writes a snapshot that differs from the previous one, naming the changes the user has not dismissed or snoozed ("Permission Pulse: something changed"). With alerts on, the app also notifies when the Full Disk Access recovery window opens.

**Implementation:** `ChangeAlert` in `PermissionsUI` composes the text; `ChangeAlertCoordinator` in the app target posts it through the same `WeeklyDigestScheduler` as a one-shot notification. The changes are computed from the previous snapshot to the new one only; a domain the previous snapshot did not capture comparably contributes nothing, so the first snapshot, the scan after Reset All Data, and coverage-only writes stay silent.

**API:** `UNTimeIntervalNotificationTrigger` (1 s, non-repeating). Fixed identifiers under `com.wallymagill.permissionpulse.changes.` (`latest`, `full-disk-access`), so a newer alert replaces an older one; Reset All Data and turning alerts off cancel that prefix.

**Preference:** `com.wallymagill.permissionpulse.changeAlertsEnabled` (default false), Preferences → Notifications → "Notify me when something changes".

---

## Permission summary

| Source | Permission required | Fragility | If unavailable |
|---|---|---|---|
| TCC.db | FDA | High | one-source partial output is visibly degraded; full failure preserves last-known rows or reports no history |
| LaunchAgents/Daemons (public) | None | Low | normally available without FDA; unreadable sources produce degraded or failed state |
| BTM (direct .btm) | FDA | Very high | failed read preserves labeled last-known rows or reports no successful data |
| BTM (sfltool) | Manual sudo | High | deferred (would be a manual user step, not automation) |
| Mic/Cam observation | None | Low | menu-bar icon stays at idle/error (✅ implemented v0.4.1) |
| Last-launch date (hybrid) | None | Medium | app omitted from Stale review (✅ implemented v0.5.0) |
| Snapshot store (GRDB) | None | Low | What Changed window shows no-prior-snapshot state (✅ implemented v0.5.0) |
