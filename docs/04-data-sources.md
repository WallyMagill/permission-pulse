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

## Last-launch date (for Stale App Review)

**What:** When the user last launched a given app.

**API:** No public macOS API for last-launch date per app. Proxies:
- `URL.contentModificationDateKey` on the `.app` bundle — close-enough for most apps.
- `mdls -name kMDItemLastUsedDate` (Spotlight metadata) — accurate, but requires shelling out.

**Permission needed:** None for the file proxy. None for `mdls` (unprivileged).

**Fragility:** Medium. Spotlight metadata can be stale or unindexed.

**Failure mode:** App is omitted from Stale review if no usable date is found. Better to under-flag than over-flag.

---

## Per-folder grants (Files & Folders)

**What:** TCC entries for specific user folders (Desktop, Documents, Downloads, iCloud Drive, etc.) — service `kTCCServiceSystemPolicyDesktopFolder` and friends.

**API:** Same TCC.db reader as above; service prefix filter.

**Permission needed:** FDA (read of TCC.db).

**Fragility:** Same as TCC.db.

**Failure mode:** Same as TCC.db.

---

## Permission summary

| Source | Permission required | Fragility | If unavailable |
|---|---|---|---|
| TCC.db | FDA | High | Inbox shows "needs FDA" empty state (✅ implemented v0.3.0) |
| LaunchAgents/Daemons (public) | None | Low | always works (✅ implemented v0.2.0) |
| BTM (direct .btm) | FDA | Very high | section shows FDA empty state (✅ implemented v0.4.0) |
| BTM (sfltool) | Manual sudo | High | deferred (would be a manual user step, not automation) |
| Mic/Cam observation | None | Low | menu-bar icon stays at idle/error (✅ implemented v0.4.1) |
| Last-launch date | None | Medium | app omitted from Stale review |
